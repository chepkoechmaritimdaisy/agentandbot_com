defmodule GovernanceCoreWeb.Plugs.SupabaseAuth do
  @moduledoc """
  Verifies Supabase JWT tokens from the Authorization header.
  """
  import Plug.Conn
  require Logger

  def init(opts), do: opts

  def call(conn, _opts) do
    with ["Bearer " <> token] <- get_req_header(conn, "authorization"),
         {:ok, claims} <- verify_token(token) do
      conn
      |> assign(:current_user, claims)
      |> assign(:supabase_token, token)
    else
      _ ->
        conn
        |> send_resp(401, "Unauthorized")
        |> halt()
    end
  end

  defp verify_token(token) do
    secret = Application.get_env(:governance_core, :supabase)[:jwt_secret]

    if secret do
      signer = Joken.Signer.create("HS256", secret)
      Joken.verify(token, signer)
    else
      Logger.error("SUPABASE_JWT_SECRET is not configured!")
      {:error, :missing_config}
    end
  end
end
