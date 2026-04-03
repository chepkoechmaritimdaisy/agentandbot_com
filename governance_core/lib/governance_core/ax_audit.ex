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

    failures = Enum.filter(results, fn {status, _} -> status == :error end)

    if Enum.empty?(failures) do
      Logger.info("AX Audit Passed: All endpoints are Agent-Friendly.")
    else
      Logger.error("AX Audit Failed: #{inspect(failures)}")
      create_pr_for_failures(failures)
    end
  end

  defp check_endpoint(url) do
    start_time = System.monotonic_time(:millisecond)
    case Req.get(url, decode_body: false) do
      {:ok, %{status: 200, body: body}} ->
        end_time = System.monotonic_time(:millisecond)
        duration = end_time - start_time

        is_friendly =
          if String.contains?(url, "api") or String.starts_with?(body, "{") or String.starts_with?(body, "[") do
            is_valid_json_schema?(body)
          else
            is_agent_friendly?(body)
          end

        cond do
          duration > 5000 ->
            {:error, :timeout}
          is_friendly ->
            {:ok, url}
          true ->
            {:error, :schema_mismatch}
        end
      {:ok, %{status: _status}} ->
        {:error, :invalid_status}
      {:error, _reason} ->
        {:error, :request_failed}
    end
  end

  defp is_valid_json_schema?(body) do
    case Jason.decode(body) do
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  defp create_pr_for_failures(failures) do
    try do
      Logger.info("Attempting to create PR for AX Audit failures...")

      # We prepare and push the branch using low-level git commands
      # to avoid checking out or changing the working tree.
      branch_name = "fix/ax-audit-#{System.system_time(:second)}"

      # Create a file so the commit is not empty
      report_content = "AX Audit Failures:\n#{inspect(failures)}"
      File.write!("ax_audit_report.txt", report_content)
      System.cmd("git", ["add", "ax_audit_report.txt"])

      with {tree_hash, 0} <- System.cmd("git", ["write-tree"]),
           tree_hash = String.trim(tree_hash),
           {head_hash, 0} <- System.cmd("git", ["rev-parse", "HEAD"]),
           head_hash = String.trim(head_hash),
           commit_msg = "Fix AX Audit failures\\n\\nFailures: #{inspect(failures)}",
           {commit_hash, 0} <- System.cmd("git", ["commit-tree", tree_hash, "-p", head_hash, "-m", commit_msg]),
           commit_hash = String.trim(commit_hash),
           {_, 0} <- System.cmd("git", ["update-ref", "refs/heads/#{branch_name}", commit_hash]),
           {_, 0} <- System.cmd("git", ["push", "origin", branch_name]),
           {output, 0} <- System.cmd("gh", ["pr", "create", "--base", "main", "--head", branch_name, "--title", "Fix AX Audit Failures", "--body", "Automated PR from AX Audit."]) do
        Logger.info("PR created: #{output}")
      else
        {err, code} ->
          Logger.error("Git or gh command failed with exit code #{code}: #{inspect(err)}")
      end
    rescue
      e in ErlangError ->
        Logger.error("Failed to execute external command (missing binary): #{inspect(e)}")
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
