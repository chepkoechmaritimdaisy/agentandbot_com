defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically scans the loaded codebase for new functions and tools,
  extracts their documentation using `Code.fetch_docs/1`, and generates
  or updates `SKILL.md` with YAML frontmatter within a 1024-character limit.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    schedule_scan()
    {:ok, state}
  end

  def handle_info(:scan, state) do
    perform_scan()
    schedule_scan()
    {:noreply, state}
  end

  defp schedule_scan do
    Process.send_after(self(), :scan, @interval)
  end

  defp perform_scan do
    Logger.info("Starting SkillTracker scan...")

    modules =
      Code.all_loaded()
      |> Enum.map(fn {mod, _file} -> mod end)
      |> Enum.filter(fn mod ->
        String.starts_with?(Atom.to_string(mod), "Elixir.GovernanceCore")
      end)

    docs = Enum.reduce(modules, [], fn mod, acc ->
      case Code.fetch_docs(mod) do
        {:docs_v1, _, _, _, _, _, fn_docs} ->
          extracted = extract_functions(mod, fn_docs)
          acc ++ extracted
        _ ->
          acc
      end
    end)

    write_skill_md(docs)
  end

  defp extract_functions(mod, fn_docs) do
    Enum.reduce(fn_docs, [], fn doc_tuple, acc ->
      case doc_tuple do
        {{:function, name, arity}, _anno, _sig, %{"en" => doc_string}, _meta} ->
          [{mod, name, arity, doc_string} | acc]
        _ ->
          acc
      end
    end)
  end

  defp write_skill_md(docs) do
    content = Enum.map_join(docs, "\n\n", &format_skill/1)

    # 1024 char limit for SKILL.md content
    content_sliced = String.slice(content, 0, 1024)

    file_path = "SKILL.md"

    case File.write(file_path, content_sliced) do
      :ok -> Logger.info("SkillTracker updated SKILL.md successfully.")
      {:error, reason} -> Logger.error("Failed to write SKILL.md: #{inspect(reason)}")
    end
  end

  defp format_skill({mod, name, arity, doc_string}) do
    # Requires YAML frontmatter style, we format it as a markdown block
    """
    ---
    name: #{name}/#{arity}
    module: #{mod}
    version: 1.0.0
    description: |
      #{String.replace(doc_string || "", "\n", "\n  ")}
    ---
    # #{name}/#{arity}
    #{doc_string}
    """
  end
end
