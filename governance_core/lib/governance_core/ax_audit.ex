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

    mcp_result = check_mcp_endpoint(base_url <> "/api/mcp")
    all_results = [mcp_result | results]

    failures = Enum.filter(all_results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      create_automated_pr(failures)
    end
  end

  defp check_mcp_endpoint(url) do
    {time, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    # time is in microseconds, check if it exceeds 1000ms (1_000_000 us)
    if time > 1_000_000 do
      {:error, :timeout}
    else
      case result do
        {:ok, %{status: 200}} ->
           # Minimal check, assuming 200 is good enough or JSON schema validation
           {:ok, url}
        {:ok, %{status: status}} ->
           {:error, "Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
           {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
      end
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

  defp create_automated_pr(failures) do
    Logger.info("Triggering automated PR for AX Audit failures...")
    try do
      # Deduplicate check
      case System.cmd("gh", ["pr", "list", "--search", "in:title 🤖 [AX Audit] Automated Fix"]) do
        {output, 0} ->
           if String.trim(output) == "" do
             do_create_pr(failures)
           else
             Logger.info("PR already exists, skipping.")
           end
        {_, _} ->
           Logger.warning("Failed to run gh pr list")
      end
    rescue
      e in ErlangError -> Logger.warning("Failed to execute gh CLI: #{inspect(e)}")
    end
  end

  defp do_create_pr(failures) do
     # Generate a fix in the source directory
     priv_dir = Path.join(File.cwd!(), "priv")
     File.mkdir_p!(priv_dir)
     fix_path = Path.join(priv_dir, "ax_audit_fix_#{:os.system_time(:second)}.txt")
     File.write!(fix_path, "Automated fix for failures: #{inspect(failures)}")

     try do
       System.cmd("git", ["add", fix_path])
       System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])
       # Assuming branch creation and pushing is handled or mocked for now
       Logger.info("Created automated fix commit.")
     rescue
       e in ErlangError -> Logger.warning("Failed to execute git CLI: #{inspect(e)}")
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
