defmodule TdCxWeb.SourceControllerTest do
  use TdCxWeb.ConnCase

  alias TdCx.Permissions.MockPermissionResolver
  alias TdCx.Sources
  alias TdCx.Sources.Source

  setup_all do
    start_supervised(MockPermissionResolver)
    :ok
  end

  @app_admin_template %{
    id: 1,
    name: "app-admin",
    label: "app-admin",
    scope: "cx",
    content: [
      %{
        "name" => "a",
        "type" => "string",
        "group" => "New Group 1",
        "label" => "a",
        "widget" => "string",
        "disabled" => true,
        "cardinality" => "1"
      }
    ]
  }

  @create_attrs %{
    "config" => %{"a" => "1"},
    "external_id" => "some external_id",
    "type" => "app-admin"
  }
  @update_attrs %{
    "config" => %{"a" => "3"},
    "external_id" => "some external_id",
    "type" => "some updated type"
  }
  @invalid_update_attrs %{
    "config" => %{"b" => "1"},
    "external_id" => "some external_id",
    "type" => "some updated type"
  }
  @invalid_attrs %{
    "config" => nil,
    "external_id" => "some external_id",
    "secrets_key" => nil,
    "type" => nil
  }

  def fixture(:source) do
    {:ok, source} = Sources.create_source(@create_attrs)
    source
  end

  def fixture(:template) do
    {:ok, template} = Templates.create_template(@app_admin_template)
    template
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    setup [:create_source]

    @tag :admin_authenticated
    test "lists all sources", %{conn: conn} do
      conn = get(conn, Routes.source_path(conn, :index, type: "app-admin"))

      assert [
               %{
                 "config" => %{"a" => "1"},
                 "external_id" => "some external_id",
                 "id" => id,
                 "type" => "app-admin"
               }
             ] = json_response(conn, 200)["data"]
    end
  end

  describe "show" do
    setup [:create_source]

    @tag :admin_authenticated
    test "show source", %{conn: conn} do
      conn = get(conn, Routes.source_path(conn, :show, "some external_id"))

      assert %{
               "config" => %{"a" => "1"},
               "external_id" => "some external_id",
               "id" => id,
               "type" => "app-admin"
             } = json_response(conn, 200)["data"]
      assert %{"a" => "1"} == json_response(conn, 200)["data"]["config"]
    end
  end

  describe "create source" do
    @tag authenticated_no_admin_user: "user"
    test "returns unauthorized for non admin user", %{conn: conn} do
      conn = post(conn, Routes.source_path(conn, :create), source: @create_attrs)
      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    @tag :admin_authenticated
    test "renders source when data is valid", %{conn: conn} do
      Templates.create_template(@app_admin_template)
      conn = post(conn, Routes.source_path(conn, :create), source: @create_attrs)
      assert %{"external_id" => external_id} = json_response(conn, 201)["data"]

      conn = get(conn, Routes.source_path(conn, :show, external_id))

      assert %{
               "id" => id,
               "config" => %{"a" => "1"},
               "external_id" => "some external_id",
               "type" => "app-admin"
             } = json_response(conn, 200)["data"]
    end

    @tag :admin_authenticated
    test "renders errors when data is invalid", %{conn: conn} do
      Templates.create_template(@app_admin_template)
      conn = post(conn, Routes.source_path(conn, :create), source: @invalid_attrs)
      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "update source" do
    setup [:create_source]

    @tag authenticated_no_admin_user: "user"
    test "returns unauthorized for non admin user", %{
      conn: conn,
      source: %Source{external_id: external_id}
    } do
      conn = put(conn, Routes.source_path(conn, :update, external_id), source: @update_attrs)
      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    @tag :admin_authenticated
    test "renders source when data is valid", %{
      conn: conn,
      source: %Source{external_id: external_id}
    } do
      conn = put(conn, Routes.source_path(conn, :update, external_id), source: @update_attrs)
      assert %{"external_id" => ^external_id} = json_response(conn, 200)["data"]

      conn = get(conn, Routes.source_path(conn, :show, external_id))

      assert %{
               "id" => id,
               "config" => %{"a" => "3"},
               "external_id" => "some external_id",
               "type" => "app-admin"
             } = json_response(conn, 200)["data"]
    end

    @tag :admin_authenticated
    test "renders errors when template content is invalid", %{
      conn: conn,
      source: %Source{external_id: external_id}
    } do
      conn =
        put(conn, Routes.source_path(conn, :update, external_id), source: @invalid_update_attrs)

      assert json_response(conn, 422)["errors"] == %{"a" => ["can't be blank"]}
    end

    @tag :admin_authenticated
    test "renders errors when data is invalid", %{conn: conn, source: source} do
      conn =
        put(conn, Routes.source_path(conn, :update, source.external_id), source: @invalid_attrs)

      assert json_response(conn, 422)["errors"] != %{}
    end
  end

  describe "delete source" do
    setup [:create_source]

    @tag authenticated_no_admin_user: "user"
    test "returns unauthorized for non admin user", %{conn: conn, source: source} do
      conn = delete(conn, Routes.source_path(conn, :delete, source.external_id))
      assert %{"errors" => %{"detail" => "Forbidden"}} = json_response(conn, 403)
    end

    @tag :admin_authenticated
    test "deletes chosen source", %{conn: conn, source: source} do
      conn = delete(conn, Routes.source_path(conn, :delete, source.external_id))
      assert response(conn, 204)

      conn = get(conn, Routes.source_path(conn, :show, source.external_id))
      assert response(conn, 404)
    end
  end

  defp create_source(_) do
    Templates.create_template(@app_admin_template)
    source = fixture(:source)
    {:ok, source: source}
  end
end