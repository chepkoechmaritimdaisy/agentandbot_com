defmodule GovernanceCoreWeb.CommentController do
  use GovernanceCoreWeb, :controller

  alias GovernanceCore.Monitoring

  def create(conn, %{"comment" => comment_params}) do
    {:ok, comment} = Monitoring.add_comment(comment_params)

    conn
    |> put_status(:created)
    |> json(%{status: "ok", data: comment})
  end
end
