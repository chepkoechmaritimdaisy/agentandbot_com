defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically scans the codebase for new functions or tools and appends them to SKILL.md.
  Ensures documentation conforms to universal standards (YAML format, 1024 character limit).
  """
  use GenServer
  require Logger

  # Default interval: 1 hour
  @interval 60 * 60 * 1000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_track()
    {:ok, state}
  end

  @impl true
  def handle_info(:track, state) do
    perform_track()
    schedule_track()
    {:noreply, state}
  end

  defp schedule_track do
    Process.send_after(self(), :track, @interval)
  end

  defp perform_track do
    Logger.info("SkillTracker: Scanning for new tools and functions...")

    loaded_modules = Code.all_loaded()
    governance_modules = Enum.filter(loaded_modules, fn {module, _path} ->
      module_name = Atom.to_string(module)
      String.starts_with?(module_name, "Elixir.GovernanceCore")
    end)

    docs =
      Enum.flat_map(governance_modules, fn {module, _path} ->
        case Code.fetch_docs(module) do
          {:docs_v1, _anno, _language, _format, _module_doc, _metadata, docs} ->
            Enum.map(docs, fn
              {{:function, name, arity}, _anno, _signatures, doc, _metadata} ->
                extract_doc(module, name, arity, doc)
              _ -> nil
            end)
            |> Enum.reject(&is_nil/1)

          _ -> []
        end
      end)

    update_skill_md(docs)
  end

  defp extract_doc(module, name, arity, %{"en" => doc_content}) do
    indented_desc =
      doc_content
      |> String.slice(0, 1024)
      |> String.split("\n")
      |> Enum.map(&("  " <> &1))
      |> Enum.join("\n")

    """
    ---
    tool: #{module}.#{name}/#{arity}
    description: |
#{indented_desc}
    ---
    """
  end

  defp extract_doc(_module, _name, _arity, _), do: nil

  defp update_skill_md(docs) do
    skill_md_path = "SKILL.md"

    existing_content =
      if File.exists?(skill_md_path) do
        File.read!(skill_md_path)
      else
        ""
      end

    new_content =
      Enum.reduce(docs, existing_content, fn doc, acc ->
        if String.contains?(acc, doc) do
          acc
        else
          acc <> "\n" <> doc
        end
      end)

    if new_content != existing_content do
      File.write!(skill_md_path, new_content)
      Logger.info("SkillTracker: Updated #{skill_md_path} with new tools.")
    else
      Logger.debug("SkillTracker: No new tools found.")
    end
  end
end
