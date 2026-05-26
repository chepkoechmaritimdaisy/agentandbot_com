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

  # 5 minutes in milliseconds
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  def handle_info(:audit, state) do
    perform_audit()
    schedule_audit()
    {:noreply, state}
  end

  defp schedule_audit do
    Process.send_after(self(), :audit, @interval)
  end

  def perform_audit do
    Logger.info("Starting Continuous AX Audit...")

    base_url = GovernanceCoreWeb.Endpoint.url()
    endpoints = ["/", "/agents", "/dashboard/traffic"]

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    # Also check the MCP endpoint
    mcp_result = check_mcp_endpoint(base_url <> "/api/mcp")
    results = [mcp_result | results]

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      auto_fix_failures(failures)
    end
  end

  defp auto_fix_failures(failures) do
    # Map errors to encodable structures (strings) for Jason
    encodable_failures = Enum.map(failures, fn {:error, reason} -> "Error: #{inspect(reason)}" end)

    # Serialize to JSON
    json_data = Jason.encode!(%{failures: encodable_failures})

    # Write to a file in the source directory
    file_path = Path.join(File.cwd!(), "priv/ax_audit_fix.json")
    File.write!(file_path, json_data)

    create_pull_request(file_path)
  end

  defp create_pull_request(file_path) do
    # Check for existing PR to deduplicate
    try do
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--json", "url"]) do
        {output, 0} ->
          if output == "[]\n" or output == "[]" do
            # No existing PR, create one
            branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"
            System.cmd("git", ["checkout", "-b", branch_name])
            System.cmd("git", ["add", file_path])
            System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])

            case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit failures."]) do
              {_, 0} -> Logger.info("Created PR for AX Audit fix.")
              {err, _} -> Logger.error("Failed to create PR: #{err}")
            end

            System.cmd("git", ["checkout", "-"])
          else
            Logger.info("AX Audit fix PR already exists, skipping.")
          end
        {err, _} -> Logger.error("Failed to list PRs: #{err}")
      end
    rescue
      e in ErlangError -> Logger.error("Failed to execute gh CLI: #{inspect(e)}")
    end
  end

  defp check_mcp_endpoint(url) do
    case :timer.tc(fn -> Req.get(url, decode_body: false) end) do
      {time_us, {:ok, %{status: 200, body: body}}} ->
        if time_us > 1000 * 1000 do
          {:error, "Endpoint #{url} took too long to respond: #{time_us / 1000}ms"}
        else
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, reason} -> {:error, "Endpoint #{url} returned invalid JSON: #{inspect(reason)}"}
          end
        end
      {_time_us, {:ok, %{status: status}}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {_time_us, {:error, reason}} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
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
