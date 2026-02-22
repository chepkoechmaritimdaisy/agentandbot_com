defmodule GovernanceCore.AXAuditTest do
  use ExUnit.Case, async: true
  import GovernanceCore.AXAudit

  test "is_agent_friendly?/1 detects semantic tags" do
    valid_html = "<html><body><main><h1>Title</h1>Content</main></body></html>"
    assert is_agent_friendly?(valid_html) == true
  end

  test "is_agent_friendly?/1 rejects missing main tag" do
    invalid_html = "<html><body><div><h1>Title</h1>Content</div></body></html>"
    assert is_agent_friendly?(invalid_html) == false
  end
end
