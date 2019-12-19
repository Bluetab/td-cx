defmodule TdCxWeb.SourceView do
  use TdCxWeb, :view
  alias TdCxWeb.SourceView

  def render("index.json", %{sources: sources}) do
    %{data: render_many(sources, SourceView, "source.json")}
  end

  def render("show.json", %{source: source}) do
    %{data: render_one(source, SourceView, "source.json")}
  end

  def render("source.json", %{source: source}) do
    %{id: source.id,
      external_id: source.external_id,
      config: source.config,
      secrets_key: source.secrets_key,
      type: source.type}
  end
end
