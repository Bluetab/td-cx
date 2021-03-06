defmodule TdCxWeb.Authentication do
  @moduledoc """
  This module defines the functions required to
  add auth headers to requests
  """
  import Plug.Conn

  alias Phoenix.ConnTest
  alias TdCx.Auth.Claims
  alias TdCx.Auth.Guardian

  def put_auth_headers(conn, jwt) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put_req_header("authorization", "Bearer #{jwt}")
  end

  def create_user_auth_conn(%Claims{role: role} = claims) do
    {:ok, jwt, full_claims} = Guardian.encode_and_sign(claims, %{role: role})
    {:ok, claims} = Guardian.resource_from_claims(full_claims)

    conn =
      ConnTest.build_conn()
      |> put_auth_headers(jwt)

    register_token(jwt)
    [conn: conn, jwt: jwt, claims: claims]
  end

  def create_claims(opts \\ []) do
    role = Keyword.get(opts, :role, "user")

    user_name =
      case Keyword.get(opts, :user_name) do
        nil -> if role === "admin", do: "app-admin", else: "user"
        name -> name
      end

    %Claims{
      user_id: Integer.mod(:binary.decode_unsigned(user_name), 100_000),
      user_name: user_name,
      role: role
    }
  end

  defp register_token(token) do
    with {:ok, resource} <- Guardian.decode_and_verify(token) do
      MockPermissionResolver.register_token(resource)
    end

    token
  end

  def create_acl_entry(user_id, domain_id, permissions) do
    MockPermissionResolver.create_acl_entry(%{
      principal_id: user_id,
      principal_type: "user",
      resource_id: domain_id,
      resource_type: "domain",
      permissions: permissions
    })
  end
end
