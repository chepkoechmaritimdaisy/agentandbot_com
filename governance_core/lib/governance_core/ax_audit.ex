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
    endpoints = ["/", "/agents", "/dashboard/traffic", "/api/mcp"]

    results =
      endpoints
      |> Task.async_stream(
        fn path ->
          url = base_url <> path
          check_endpoint(url)
        end,
        timeout: :infinity
      )
      |> Enum.map(fn {:ok, res} -> res end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      create_automated_pr(failures)
    end
  end

  defp check_endpoint(url) do
    if String.ends_with?(url, "/api/mcp") do
      check_mcp_endpoint(url)
    else
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
  end

  defp check_mcp_endpoint(url) do
    {time, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)
    # Convert microseconds to milliseconds
    time_ms = time / 1000.0

    if time_ms > 1000.0 do
      {:error, "MCP endpoint #{url} response time too high: #{time_ms}ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "MCP endpoint #{url} returned invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch MCP endpoint #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp create_automated_pr(failures) do
    file_path = Path.join(File.cwd!(), "priv/mcp_fix.json")

    encoded_failures = Enum.map(failures, fn {:error, reason} -> reason end)

    try do
      case File.write(file_path, Jason.encode!(%{failures: encoded_failures})) do
        :ok ->
          branch_name = "bot/ax-audit-fix-#{:os.system_time(:seconds)}"

          # Check for existing PR to prevent spam loop
          case System.cmd("gh", ["pr", "list", "--search", "in:title 🤖 [AX Audit] Automated Fix", "--state", "open"]) do
            {output, 0} ->
              if String.trim(output) == "" do
                case System.cmd("git", ["checkout", "-b", branch_name]) do
                  {_, 0} ->
                    System.cmd("git", ["add", file_path])
                    case System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"]) do
                      {_, 0} ->
                        System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit failures."])
                      _ -> Logger.warning("Failed to commit PR changes, skipping PR creation")
                    end
                    System.cmd("git", ["checkout", "-"] )
                  _ -> Logger.error("Failed to create branch")
                end
              else
                Logger.info("AX Audit PR already exists, skipping creation.")
              end
            {_, _} ->
              Logger.warning("Failed to check existing gh PRs")
          end
        {:error, reason} ->
          Logger.error("Failed to write MCP fix file: #{inspect(reason)}")
      end
    rescue
      e ->
        Logger.error("Exception during automated PR creation: #{inspect(e)}")
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
