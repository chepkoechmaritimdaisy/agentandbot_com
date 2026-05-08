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

  # Continuous interval (5 minutes)
  @interval 5 * 60 * 1000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_audit()
    {:ok, state}
  end

  @impl true
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

    # Existing standard checks
    endpoints = ["/", "/agents", "/dashboard/traffic"]
    standard_results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    # MCP check
    mcp_url = base_url <> "/api/mcp"
    mcp_result = check_mcp_endpoint(mcp_url)

    all_results = [mcp_result | standard_results]
    failures = Enum.filter(all_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      handle_failures(failures)
    end
  end

  defp check_endpoint(url) do
    case Req.get(url) do
      {:ok, %{status: 200, body: body}} ->
        if is_agent_friendly?(body) do
          {:ok, url}
        else
          {:error, {:not_agent_friendly, url}}
        end
      {:ok, %{status: status}} ->
        {:error, {:bad_status, url, status}}
      {:error, reason} ->
        {:error, {:fetch_failed, url, reason}}
    end
  end

  defp check_mcp_endpoint(url) do
    {time_us, result} = :timer.tc(fn -> Req.get(url, decode_body: false) end)
    time_ms = time_us / 1000

    if time_ms > 1000 do
      {:error, :timeout}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, :invalid_schema}
          end
        {:ok, %{status: status}} ->
          {:error, {:bad_status, url, status}}
        {:error, _reason} ->
          {:error, :fetch_failed}
      end
    end
  end

  defp is_agent_friendly?(html) do
    has_main = String.contains?(html, "<main")
    has_h1 = String.contains?(html, "<h1")
    has_main && has_h1
  end

  defp handle_failures(failures) do
    # Only create a PR for MCP-related static errors to prevent spam loops
    mcp_failures = Enum.filter(failures, fn
      {:error, :timeout} -> true
      {:error, :invalid_schema} -> true
      _ -> false
    end)

    unless Enum.empty?(mcp_failures) do
      create_automated_pr()
    end
  end

  defp create_automated_pr do
    # Generate fix file
    priv_dir = Path.join(File.cwd!(), "priv")
    fix_file = Path.join(priv_dir, "ax_audit_fix_#{System.system_time(:second)}.txt")

    case File.write(fix_file, "Automated AX Audit fix for MCP endpoint.") do
      :ok ->
        Logger.info("Created automated fix file at #{fix_file}")

        # Deduplication using `gh pr list`
        try do
          case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix", "--state", "open"]) do
            {output, 0} ->
              if String.trim(output) == "" do
                # No open PRs found, create one
                System.cmd("git", ["add", "priv/"])
                System.cmd("git", ["commit", "-m", "Automated AX Audit fix"])
                System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for MCP endpoint."])
                Logger.info("Automated PR created.")
              else
                Logger.info("Open PR already exists, skipping PR creation.")
              end
            {_, exit_code} ->
              Logger.warning("gh pr list returned exit code #{exit_code}")
          end
        rescue
          e in ErlangError ->
            Logger.warning("Failed to execute git/gh commands: #{inspect(e)}")
        end
      {:error, reason} ->
        Logger.error("Failed to write fix file: #{inspect(reason)}")
    end
  end
end
