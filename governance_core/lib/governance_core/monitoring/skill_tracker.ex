defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Auto-detects new functions and tools in the system and appends entries to SKILL.md.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    schedule_scan()
    {:ok, state}
  end

  @impl true
  def handle_info(:scan, state) do
    scan_skills()
    schedule_scan()
    {:noreply, state}
  end

  defp schedule_scan do
    Process.send_after(self(), :scan, @interval)
  end

  defp scan_skills do
    Logger.info("Scanning for new skills to update SKILL.md...")

    skills =
      Code.all_loaded()
      |> Enum.map(fn {mod, _} -> mod end)
      |> Enum.filter(fn mod -> String.starts_with?(to_string(mod), "Elixir.GovernanceCore") end)
      |> Enum.flat_map(&fetch_module_docs/1)

    existing =
      case File.read("SKILL.md") do
        {:ok, content} -> content
        {:error, _} -> ""
      end

    new_content =
      Enum.reduce(skills, existing, fn skill, acc ->
        if String.contains?(acc, skill.name) do
          acc
        else
          yaml_entry = format_skill_yaml(skill)
          acc <> "\n" <> yaml_entry
        end
      end)

    if new_content != existing do
      File.write!("SKILL.md", new_content)
      Logger.info("SKILL.md updated successfully.")
    end
  end

  defp fetch_module_docs(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, :elixir, "text/markdown", _, _, docs} ->
        for {{:function, name, arity}, _, _, doc, _} <- docs,
            doc != :none do
          doc_string = extract_doc(doc)
          %{
            name: "#{mod}.#{name}/#{arity}",
            description: doc_string
          }
        end
      _ ->
        []
    end
  end

  defp extract_doc(%{"en" => doc_str}), do: doc_str
  defp extract_doc(_), do: ""

  defp format_skill_yaml(skill) do
    # When interpolating multiline strings into YAML block scalars (key: |),
    # the injected string must be explicitly indented line-by-line in Elixir.
    # Limit to 1024 characters total length per standard.
    # Truncate description to ensure the whole block is under 1024.
    max_desc_len = 1024 - byte_size("    ---\n    tool: #{skill.name}\n    description: |\n    \n    ---\n    ")

    truncated_desc = String.slice(skill.description, 0, max_desc_len)

    indented_desc =
      truncated_desc
      |> String.split("\n")
      |> Enum.map(fn line -> "  #{line}" end)
      |> Enum.join("\n")

    """
    ---
    tool: #{skill.name}
    description: |
    #{indented_desc}
    ---
    """
  end
end
