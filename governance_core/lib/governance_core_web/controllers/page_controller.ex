defmodule GovernanceCoreWeb.PageController do
  use GovernanceCoreWeb, :controller

  def home(conn, _params) do
    conn
    |> put_layout(html: {GovernanceCoreWeb.Layouts, :app})
    |> assign(:current_path, "/")
    |> render(:home)
  end
end
