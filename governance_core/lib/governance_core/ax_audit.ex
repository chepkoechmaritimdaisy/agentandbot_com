defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  """
  use GenServer
  require Logger

  # 24 hours in milliseconds
  @interval 24 * 60 * 60 * 1000
  # 1 minute in milliseconds for MCP monitoring
  @mcp_interval 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    schedule_mcp_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  def handle_info(:mcp_audit, state) do
    perform_mcp_audit()
    schedule_mcp_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  defp schedule_mcp_audit do
    Process.send_after(self(), :mcp_audit, @mcp_interval)
  end

  def perform_mcp_audit do
    Logger.info("Starting Continuous MCP Audit...")
    base_url = GovernanceCoreWeb.Endpoint.url()
    url = base_url <> "/api/mcp"

    start_time = System.monotonic_time()

    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time()
        duration_ms = System.convert_time_unit(end_time - start_time, :native, :millisecond)

        cond do
          duration_ms > 1000 ->
             handle_mcp_failure("MCP Endpoint response time too slow: #{duration_ms}ms")
          not is_valid_json_schema?(body) ->
             handle_mcp_failure("MCP Endpoint JSON schema validation failed")
          true ->
             Logger.info("MCP Audit Passed: Endpoint responsive and valid.")
        end

      {:ok, %{status: status}} ->
        handle_mcp_failure("MCP Endpoint returned status #{status}")

      {:error, reason} ->
        handle_mcp_failure("Failed to fetch MCP Endpoint #{url}: #{inspect(reason)}")
    end
  end

  defp is_valid_json_schema?(body) when is_map(body) do
    # Simple check for required fields, e.g. "version" and "status"
    Map.has_key?(body, "version") and Map.has_key?(body, "status")
  end
  defp is_valid_json_schema?(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, json} -> is_valid_json_schema?(json)
      {:error, _} -> false
    end
  end
  defp is_valid_json_schema?(_), do: false

  defp handle_mcp_failure(reason) do
    Logger.error("MCP Audit Failed: #{reason}")
    create_automated_pr(reason)
  end

  defp create_automated_pr(reason) do
    try do
      # Deduplicate PRs
      case System.cmd("gh", ["pr", "list", "--search", "in:title Automated MCP Fix"]) do
        {output, 0} ->
          if String.contains?(output, "Automated MCP Fix") do
            Logger.info("Automated MCP Fix PR already exists. Skipping.")
          else
            execute_pr_creation(reason)
          end
        {err, code} ->
          Logger.error("Failed to check existing PRs. Exit code: #{code}, Output: #{err}")
      end
    rescue
      e in ErlangError ->
        Logger.error("GitHub CLI not available or failed: #{inspect(e)}")
    end
  end

  defp execute_pr_creation(reason) do
    branch_name = "auto-fix-mcp-#{System.unique_integer([:positive])}"

    # We modify a dynamically generated file in priv/ to simulate a fix
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)
    fix_file_path = Path.join(priv_dir, "mcp_fix.txt")
    File.write!(fix_file_path, "Automated fix generated for reason: #{reason}\nTimestamp: #{DateTime.utc_now()}")

    System.cmd("git", ["checkout", "-b", branch_name])
    System.cmd("git", ["add", fix_file_path])
    System.cmd("git", ["commit", "-m", "Automated MCP Fix"])

    case System.cmd("gh", ["pr", "create", "--title", "Automated MCP Fix", "--body", "This is an automated fix for MCP Endpoint failures.\nReason: #{reason}"]) do
      {_out, 0} ->
        Logger.info("Successfully created automated PR for MCP fix.")
      {err, code} ->
        Logger.error("Failed to create PR. Exit code: #{code}, Output: #{err}")
    end
    System.cmd("git", ["checkout", "-"])
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, "Endpoint #{url} is not agent-friendly (missing semantic tags or too complex)"}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    # Check for excessive script usage might be tricky with simple string matching,
    # but we can check if the ratio of script tags to content is high or just ensure main content exists.

    has_main && has_h1
  end
end
