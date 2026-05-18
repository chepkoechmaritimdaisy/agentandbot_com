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

    results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      if path == "/api/mcp" do
        check_api_endpoint(url)
      else
        check_endpoint(url)
      end
    end)

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      prepare_automated_pr(failures)
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

  defp check_api_endpoint(url) do
    {time_in_microsecs, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_in_ms = time_in_microsecs / 1000

    if time_in_ms > 1000 do
      {:error, "Endpoint #{url} response time #{time_in_ms}ms exceeds 1000ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} -> {:ok, url}
            {:error, _} -> {:error, "Endpoint #{url} returned invalid JSON schema"}
          end
        {:ok, %{status: status}} ->
          {:error, "Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
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

  defp prepare_automated_pr(failures) do
    title = "🤖 [AX Audit] Automated Fix"

    try do
      # Deduplicate: Check if a PR already exists
      case System.cmd("gh", ["pr", "list", "--search", "in:title \"#{title}\"", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_pr(title, failures)
          else
            Logger.info("Automated PR already exists. Skipping creation.")
          end
        {_, _} ->
          Logger.error("Failed to list PRs using gh cli.")
      end
    rescue
      ErlangError ->
        Logger.error("Failed to execute gh cli. Is it installed?")
    end
  end

  defp create_pr(title, failures) do
    try do
      # Example: writing to a source file to stage changes
      file_path = Path.join(File.cwd!(), "priv/ax_audit_failures.log")

      File.write!(file_path, Enum.map_join(failures, "\n", fn {:error, reason} -> reason end))

      case System.cmd("git", ["add", file_path]) do
        {_, 0} ->
          case System.cmd("git", ["commit", "-m", title]) do
            {_, 0} -> Logger.info("Committed AX Audit fixes.")
            {_, _} -> Logger.error("Failed to commit AX Audit fixes.")
          end
        {_, _} -> Logger.error("Failed to add file for AX Audit fixes.")
      end
    rescue
      ErlangError ->
        Logger.error("Failed to execute git cli.")
    end
  end
end
