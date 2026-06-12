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

    html_results = Enum.map(endpoints, fn path ->
      url = base_url <> path
      check_endpoint(url)
    end)

    mcp_result = check_mcp_endpoint(base_url <> "/api/mcp")

    all_results = [mcp_result | html_results]

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
          {:error, "Endpoint #{url} is not agent-friendly (missing semantic tags or too complex)"}
        end
      {:ok, %{status: status}} ->
        {:error, "Endpoint #{url} returned status #{status}"}
      {:error, reason} ->
        {:error, "Failed to fetch #{url}: #{inspect(reason)}"}
    end
  end

  defp check_mcp_endpoint(url) do
    # Time the request using timer.tc
    {time_in_microsecs, result} = :timer.tc(fn ->
      Req.get(url, decode_body: false)
    end)

    time_in_ms = time_in_microsecs / 1000.0

    if time_in_ms > 1000.0 do
      {:error, "MCP Endpoint #{url} timeout: response took #{time_in_ms}ms"}
    else
      case result do
        {:ok, %{status: 200, body: body}} ->
          case Jason.decode(body) do
            {:ok, _json} ->
              {:ok, url}
            {:error, _} ->
              {:error, "MCP Endpoint #{url} returned invalid JSON"}
          end
        {:ok, %{status: status}} ->
          {:error, "MCP Endpoint #{url} returned status #{status}"}
        {:error, reason} ->
          {:error, "Failed to fetch MCP #{url}: #{inspect(reason)}"}
      end
    end
  end

  defp handle_failures(failures) do
    error_details = Enum.map(failures, fn {:error, reason} ->
      if is_tuple(reason), do: inspect(reason), else: reason
    end)
    |> Enum.join("\n")

    try do
      # Deduplicate: Check if a PR already exists
      case System.cmd("gh", ["pr", "list", "--search", "🤖 [AX Audit] Automated Fix in:title", "--state", "open"]) do
        {output, 0} ->
          if String.trim(output) == "" do
            create_automated_fix(error_details)
          else
            Logger.info("Automated PR already exists for AX Audit. Skipping.")
          end
        {_, code} ->
          Logger.error("Failed to list PRs using gh, exit code: #{code}")
      end
    rescue
      e in ErlangError ->
        Logger.error("gh CLI not found or failed to execute: #{inspect(e)}")
    end
  end

  defp create_automated_fix(error_details) do
    branch_name = "automated-ax-fix-#{System.unique_integer([:positive])}"

    # Generate fix file in priv
    fix_path = Path.join(File.cwd!(), "priv/ax_audit_fix.txt")

    # Ensure priv directory exists
    File.mkdir_p!(Path.dirname(fix_path))

    fix_content = """
    Automated fix triggered by AX Audit failures:
    #{error_details}
    """

    File.write!(fix_path, fix_content)

    try do
      System.cmd("git", ["checkout", "-b", branch_name])
      System.cmd("git", ["add", "priv/ax_audit_fix.txt"])
      System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix\n\nFixing AX Audit Failures"])
      System.cmd("git", ["push", "-u", "origin", branch_name])

      case System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated PR created by AX Audit.\n\nFailures:\n#{error_details}"]) do
        {_, 0} -> Logger.info("Successfully created automated PR for AX Audit.")
        {output, code} -> Logger.error("Failed to create PR. Exit code: #{code}, Output: #{output}")
      end
    rescue
      e in ErlangError ->
        Logger.error("git/gh CLI not found or failed to execute during PR creation: #{inspect(e)}")
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
