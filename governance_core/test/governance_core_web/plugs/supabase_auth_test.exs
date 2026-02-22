defmodule GovernanceCoreWeb.Plugs.SupabaseAuthTest do
  use ExUnit.Case
  import Plug.Test
  alias GovernanceCoreWeb.Plugs.SupabaseAuth

  @secret "test_secret_must_be_long_enough_for_hs256_verification"

  setup do
    Application.put_env(:governance_core, :supabase, [jwt_secret: @secret])
    :ok
  end

  test "verifies valid jwt" do
    claims = %{"sub" => "123", "exp" => :os.system_time(:seconds) + 3600}
    signer = Joken.Signer.create("HS256", @secret)
    {:ok, token, _} = Joken.generate_and_sign(%{}, claims, signer)

    conn = conn(:get, "/")
           |> put_req_header("authorization", "Bearer #{token}")
           |> SupabaseAuth.call(%{})

    assert conn.assigns[:current_user]["sub"] == "123"
    refute conn.halted
  end

  test "rejects invalid jwt" do
    conn = conn(:get, "/")
           |> put_req_header("authorization", "Bearer invalid.token")
           |> SupabaseAuth.call(%{})

    assert conn.halted
    assert conn.status == 401
  end
end
