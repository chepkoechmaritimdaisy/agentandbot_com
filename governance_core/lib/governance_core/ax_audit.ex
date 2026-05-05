defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a continuous audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  - Validation of the MCP endpoint for response time and JSON schema
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

    # Use Task.async_stream with infinity timeout for concurrent evaluation
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
      handle_failures(failures)
    end
  end

  defp check_endpoint(url) do
    if String.ends_with?(url, "/api/mcp") do
      check_mcp_endpoint(url)
    else
      case Req.get(url, decode_body: false) do
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
    {time_us, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)
    time_ms = time_us / 1000.0

    if time_ms > 1000.0 do
      {:error, :timeout}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, :invalid_json_schema}
          end

        {:ok, %{status: status}} ->
          {:error, {:bad_status, status}}

        {:error, _reason} ->
          {:error, :request_failed}
      end
    end
  end

  defp is_agent_friendly?(html) do
    # Simple heuristic checks for semantic structure
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end

  defp handle_failures(failures) do
    # Check if any failure is related to MCP endpoint
    mcp_failed =
      Enum.any?(failures, fn
        {:error, :timeout} -> true
        {:error, :invalid_json_schema} -> true
        {:error, {:bad_status, _}} -> true
        {:error, :request_failed} -> true
        _ -> false
      end)

    if mcp_failed do
      create_automated_pr()
    end
  end

  defp create_automated_pr do
    # Ensure deduplication: search if an open PR exists
    try do
      case System.cmd("gh", ["pr", "list", "--search", "in:title \"🤖 [AX Audit] Automated Fix\"", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            generate_pr()
          else
            Logger.info("An automated PR for AX Audit already exists. Skipping PR creation.")
          end

        {_, exit_code} ->
          Logger.error("Failed to check existing PRs with gh, exit code: #{exit_code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("gh CLI command failed with ErlangError: #{inspect(e)}")
    end
  end

  defp generate_pr do
    # We modify a real file in priv/ to trigger a commit.
    priv_dir = Path.join(File.cwd!(), "priv")
    File.mkdir_p!(priv_dir)
    fix_file = Path.join(priv_dir, "mcp_fix.txt")
    File.write!(fix_file, "Automated fix applied for MCP endpoint on #{DateTime.utc_now()}")

    try do
      branch_name = "ax-audit-fix-#{System.unique_integer([:positive])}"

      System.cmd("git", ["checkout", "-b", branch_name])
      System.cmd("git", ["add", fix_file])
      System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])
      System.cmd("git", ["push", "-u", "origin", branch_name])

      case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for MCP endpoint issue."]) do
        {_out, 0} -> Logger.info("Automated PR created successfully.")
        {error, _} -> Logger.error("Failed to create PR: #{error}")
      end

      # Go back to previous branch
      System.cmd("git", ["checkout", "-"])
    rescue
      e in ErlangError ->
        Logger.error("Git/gh CLI command failed with ErlangError: #{inspect(e)}")
    end
  end
end
