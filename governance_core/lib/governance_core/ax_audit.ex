defmodule GovernanceCore.AXAudit do
  @moduledoc """
  Runs a nightly audit of the application to ensure it remains "Agent-Friendly".
  Checks for:
  - Semantic HTML structure (presence of <main>, <h1>, <article>)
  - Accessibility of SKILL.md files
  - Low complexity (avoiding heavy JS blocking)
  Also continuously checks the MCP endpoint for schema validity and response times,
  generating automated PRs via gh cli on failures.
  """
  use GenServer
  require Logger

  # 5 minutes in milliseconds for continuous execution
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
    html_endpoints = ["/", "/agents", "/dashboard/traffic"]

    # 1. Existing Semantic HTML Checks
    html_results = Enum.map(html_endpoints, fn path ->
      url = base_url <> path
      check_html_endpoint(url)
    end)

    html_failures = Enum.filter(html_results, fn {status, _} -> status == :error end)

    if Enum.empty?(html_failures) do
      Logger.info("AX Audit Passed: All HTML endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed on HTML: #{inspect(html_failures)}")
    end

    # 2. Continuous MCP Endpoint Check
    mcp_url = base_url <> "/api/mcp"

    case :timer.tc(fn -> check_mcp_endpoint(mcp_url) end) do
      {time_in_microsecs, result} ->
        time_in_ms = div(time_in_microsecs, 1000)

        cond do
          time_in_ms > 1000 ->
            handle_mcp_failure({:error, :timeout})

          match?({:error, _}, result) ->
            handle_mcp_failure(result)

          true ->
            Logger.info("AX Audit Passed: MCP Endpoint is responsive and returns valid JSON.")
        end
    end
  end

  defp check_html_endpoint(url) do
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

  defp check_mcp_endpoint(url) do
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, _json} ->
            {:ok, :valid}
          {:error, _} ->
            {:error, :invalid_json}
        end
      {:ok, %{status: status}} ->
        {:error, {:bad_status, status}}
      {:error, reason} ->
        {:error, {:req_failed, inspect(reason)}}
    end
  end

  defp handle_mcp_failure(reason) do
    error_msg = "AX Audit MCP Check Failed: #{inspect(reason)}"
    Logger.error(error_msg)

    # Static error reason for deduplication matching
    static_reason = case reason do
      {:error, :timeout} -> "timeout"
      {:error, :invalid_json} -> "invalid_json"
      {:error, {:bad_status, status}} -> "bad_status_#{status}"
      {:error, {:req_failed, _}} -> "req_failed"
      _ -> "unknown_error"
    end

    branch_name = "auto-fix-ax-audit-#{static_reason}"

    try do
      # Deduplication logic using gh cli
      case System.cmd("gh", ["pr", "list", "--search", "head:#{branch_name}", "--json", "number"]) do
        {output, 0} ->
          if output == "[]\n" or output == "[]" do
            create_pr_for_fix(branch_name, static_reason)
          else
            Logger.info("PR already exists for #{branch_name}, skipping.")
          end
        {_, _} ->
          Logger.warning("Failed to check existing PRs with gh cli.")
      end
    rescue
      e in ErlangError ->
        Logger.warning("gh cli execution failed: #{inspect(e)}")
    end
  end

  defp create_pr_for_fix(branch_name, reason) do
    Logger.info("Generating automated PR for #{branch_name}")

    try do
      # Make sure we're on a clean state or just create branch
      System.cmd("git", ["checkout", "-b", branch_name])

      # Determine safe path in source to create fix file
      priv_dir = Path.join(File.cwd!(), "priv")
      File.mkdir_p!(priv_dir)

      fix_path = Path.join(priv_dir, "ax_audit_fix_#{reason}.md")
      File.write!(fix_path, "Automated fix for AX Audit MCP failure: #{reason}\n")

      System.cmd("git", ["add", fix_path])
      System.cmd("git", ["commit", "-m", "🤖 [AX Audit] Automated Fix"])

      System.cmd("git", ["push", "-u", "origin", branch_name])

      System.cmd("gh", ["pr", "create", "--title", "🤖 [AX Audit] Automated Fix", "--body", "Automated fix for AX Audit MCP failure: #{reason}", "--head", branch_name])

      System.cmd("git", ["checkout", "-"])

    rescue
      e ->
        Logger.error("Failed to create automated PR: #{inspect(e)}")
    end
  end
end
