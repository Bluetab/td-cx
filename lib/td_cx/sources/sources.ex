defmodule TdCx.Sources do
  @moduledoc """
  The Sources context.
  """

  import Ecto.Query, warn: false
  alias TdCache.TemplateCache
  alias TdCx.Repo
  alias TdCx.Sources.Source
  alias TdCx.Vault
  alias TdDfLib.Validation

  require Logger

  @doc """
  Returns the list of sources.

  ## Examples

      iex> list_sources()
      [%Source{}, ...]

  """
  def list_sources do
    Repo.all(Source)
  end

  def list_sources_by_source_type(source_type) do
    Source
    |> where([s], s.type == ^source_type)
    |> Repo.all()
  end

  @doc """
  Gets a single source.

  Raises `Ecto.NoResultsError` if the Source does not exist.

  ## Examples

      iex> get_source!(123)
      %Source{}

      iex> get_source!(456)
      ** (Ecto.NoResultsError)

  """
  def get_source!(external_id, options \\ []) do
    Source
    |> Repo.get_by!(external_id: external_id)
    |> enrich(options)
  end

  def enrich_secrets(user_name, %Source{type: user_name} = source) do
    enrich_secrets(source)
  end

  def enrich_secrets(_user_name, %Source{type: _other_type} = source) do
    source
  end

  def enrich_secrets(%Source{secrets_key: nil} = source) do
    source
  end

  def enrich_secrets(source) do
    secrets = Vault.read_secrets(source.secrets_key)
    case secrets do
      {:error, msg} ->
        {:error, msg}
      _ -> Map.put(source, :config, Map.merge(Map.get(source, :config, %{}) || %{}, secrets || %{}))

    end
  end

  defp enrich(%Source{} = source, []), do: source

  defp enrich(%Source{} = source, options) do
    Repo.preload(source, options)
  end

  @doc """
  Creates a source.

  ## Examples

      iex> create_source(%{field: value})
      {:ok, %Source{}}

      iex> create_source(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_source(attrs \\ %{}) do
    with {:ok} <- check_base_changeset(attrs),
         {:ok} <- is_valid_template_content(attrs) do
      %{"secrets" => secrets, "config" => config} = separate_config(attrs)

      attrs
      |> Map.put("secrets", secrets)
      |> Map.put("config", config)
      |> do_create_source()
    else
      error ->
        error
    end
  end

  defp separate_config(%{"config" => config, "type" => type}) do
    %{:content => content_schema} = TemplateCache.get_by_name!(type)
    secret_keys = content_schema
    |> Enum.filter(fn group -> Map.get(group, "is_secret") == true  end)
    |> Enum.map((fn group -> Map.get(group, "fields") end))
    |> List.flatten()
    |> Enum.map((fn field -> Map.get(field, "name") end))
    {secrets, config } = Map.split(config, secret_keys)
    %{"secrets" => secrets, "config" => config}
  end

  defp do_create_source(%{"secrets" => secrets} = attrs) when secrets == %{} do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  defp do_create_source(
         %{"secrets" => secrets, "external_id" => external_id, "type" => type} = attrs
       ) do
    secrets_key = build_secret_key(type, external_id)

    with :ok <- Vault.write_secrets(secrets_key, secrets) do
      attrs =
        attrs
        |> Map.put("secrets_key", secrets_key)
        |> Map.drop(["secrets"])

      %Source{}
      |> Source.changeset(attrs)
      |> Repo.insert()
    else
      {:vault_error, error} -> {:vault_error, error}
    end
  end

  defp do_create_source(attrs) do
    %Source{}
    |> Source.changeset(attrs)
    |> Repo.insert()
  end

  defp check_base_changeset(attrs, source \\ %Source{}) do
    changeset = changeset = Source.changeset(source, attrs)

    case changeset.valid? do
      true -> {:ok}
      false -> {:error, changeset}
    end
  end

  defp is_valid_template_content(%{"type" => type, "config" => config} = _attrs)
       when not is_nil(type) do
    %{:content => content_schema} = TemplateCache.get_by_name!(type)
    content_changeset = Validation.build_changeset(config, content_schema)
    case content_changeset.valid? do
      true -> {:ok}
      false -> {:error, content_changeset}
    end
  end

  defp build_secret_key(type, external_id) do
    "#{type}/#{external_id}"
  end

  @doc """
  Updates a source.

  ## Examples

      iex> update_source(source, %{field: new_value})
      {:ok, %Source{}}

      iex> update_source(source, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_source(%Source{} = source, attrs) do
    with {:ok} <- check_base_changeset(attrs, source),
         {:ok} <-
           is_valid_template_content(%{
             "type" => Map.get(source, :type),
             "config" => Map.get(attrs, "config")
           }) do
      %{"secrets" => secrets, "config" => config} =
        separate_config(%{"type" => Map.get(source, :type), "config" => Map.get(attrs, "config")})

      attrs =
        attrs
        |> Map.put("secrets", secrets)
        |> Map.put("config", config)

      do_update_source(source, attrs)
    else
      error ->
        error
    end
  end

  defp do_update_source(%Source{} = source, %{"secrets" => secrets} = attrs)
       when secrets == %{} do
    updateable_attrs = Map.drop(attrs, ["secrets", "type", "external_id"])
    updateable_attrs = Map.put(updateable_attrs, "secrets_key", nil)

    case Vault.delete_secrets(source.secrets_key) do
      :ok ->
        source
        |> Source.changeset(updateable_attrs)
        |> Repo.update()

      {:vault_error, error} ->
        {:vault_error, error}
    end
  end

  defp do_update_source(
         %Source{type: type, external_id: external_id} = source,
         %{"secrets" => secrets} = attrs
       ) do
    secrets_key = build_secret_key(type, external_id)

    with :ok <- Vault.write_secrets(secrets_key, secrets) do
      attrs =
        attrs
        |> Map.put("secrets_key", secrets_key)
        |> Map.drop(["secrets", "type", "external_id"])

      source
      |> Source.changeset(attrs)
      |> Repo.update()
    else
      {:vault_error, error} -> {:vault_error, error}
    end
  end

  defp do_update_source(%Source{} = source, %{"config" => config}) do
    source
    |> Source.changeset(%{"config" => config})
    |> Repo.update()
  end

  @doc """
  Deletes a Source.

  ## Examples

      iex> delete_source(source)
      {:ok, %Source{}}

      iex> delete_source(source)
      {:error, %Ecto.Changeset{}}

  """
  def delete_source(%Source{secrets_key: nil} = source) do
    source
    |> Source.delete_changeset()
    |> Repo.delete()
  end

  def delete_source(%Source{secrets_key: secrets_key} = source) do
    case Vault.delete_secrets(secrets_key) do
      :ok ->
        source
        |> Source.delete_changeset()
        |> Repo.delete()

      {:vault_error, error} ->
        {:vault_error, error}
    end
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking source changes.

  ## Examples

      iex> change_source(source)
      %Ecto.Changeset{source: %Source{}}

  """
  def change_source(%Source{} = source) do
    Source.changeset(source, %{})
  end
end
