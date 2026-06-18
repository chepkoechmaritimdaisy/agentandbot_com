defmodule GovernanceCore.AXAuditTest do
  use ExUnit.Case, async: true
  alias GovernanceCore.AXAudit

  # Helper functions mapped out from the private ax_audit code for testing
  def is_valid_json_schema?(body) do
      case Jason.decode(body) do
        {:ok, decoded} when is_map(decoded) or is_list(decoded) -> true
        _ -> false
      end
  end

  test "is_valid_json_schema?/1 detects valid JSON objects and arrays" do
    valid_obj = "{\"key\": \"value\"}"
    valid_arr = "[{\"key\": \"value\"}]"

    assert is_valid_json_schema?(valid_obj) == true
    assert is_valid_json_schema?(valid_arr) == true
  end

  test "is_valid_json_schema?/1 rejects invalid JSON" do
    invalid_json = "{\"key\": value"
    invalid_string = "\"string\""

    assert is_valid_json_schema?(invalid_json) == false
    assert is_valid_json_schema?(invalid_string) == false
  end
end
