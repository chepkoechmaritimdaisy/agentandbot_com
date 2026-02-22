defmodule GovernanceCore.LimiterTest do
  use ExUnit.Case
  alias GovernanceCore.Limiter

  setup do
    start_supervised!(Limiter)
    :ok
  end

  test "allows requests within quota" do
    agent_id = "agent_1"
    assert :ok = Limiter.check_limit(agent_id, 10)
  end

  test "rejects requests exceeding quota" do
    agent_id = "agent_2"
    assert :ok = Limiter.check_limit(agent_id, 90)
    # Total 100
    assert :ok = Limiter.check_limit(agent_id, 10)
    # Exceeds 100
    assert {:error, :quota_exceeded} = Limiter.check_limit(agent_id, 1)
  end
end
