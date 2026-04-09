defmodule GovernanceCore.Monitoring.SkillTracker do
  @moduledoc """
  Periodically discovers all loaded modules in the GovernanceCore application
  and generates a standardized SKILL.md file adhering to the 1024-character limit
  and maintaining proper YAML formatting.
  """
  use GenServer
  require Logger

  @interval 60 * 60 * 1000 # 1 hour
  @max_length 1024
  @skill_file "SKILL.md"

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Logger.info("Starting Skill Tracker...")
    # Delay initial run slightly to allow application to fully start
    Process.send_after(self(), :track, 5000)
    {:ok, state}
  end

  def handle_info(:track, state) do
    generate_skill_md()
    Process.send_after(self(), :track, @interval)
    {:noreply, state}
  end

  defp generate_skill_md do
    # Use application key instead of Code.all_loaded() to find all modules reliably
    modules =
      case :application.get_key(:governance_core, :modules) do
        {:ok, mods} -> mods
        _ -> []
      end

    module_docs = Enum.map(modules, fn mod ->
      doc = get_module_doc(mod)
      "- #{inspect(mod)}: #{doc}"
    end)
    |> Enum.join("\n")

    # Construct the content block with explicit indentation for YAML block scalar
    indented_content =
      module_docs
      |> String.split("\n")
      |> Enum.map(fn line -> "  #{line}" end)
      |> Enum.join("\n")

    content = """
    ---
    name: GovernanceCore Skills
    description: Automatically generated skill documentation.
    modules: |
    #{indented_content}
    ---
    # SKILL Documentation
    This file is auto-generated.
    """

    # Enforce 1024-char limit before writing to prevent breaking structure
    # Wait, truncating the whole string might break YAML structure at the end.
    # We should truncate the *content* before wrapping it in the YAML frontmatter.

    max_content_length = @max_length - 150 # reserve space for headers/footers

    truncated_content =
      if String.length(indented_content) > max_content_length do
        String.slice(indented_content, 0, max_content_length) <> "\n  ...(truncated)"
      else
        indented_content
      end

    final_doc = """
    ---
    name: GovernanceCore Skills
    description: Automatically generated skill documentation.
    modules: |
    #{truncated_content}
    ---
    # SKILL Documentation
    This file is auto-generated.
    """

    # Failsafe limit just in case
    final_doc = String.slice(final_doc, 0, @max_length)

    File.write!(@skill_file, final_doc)
    Logger.info("SKILL.md successfully updated.")
  end

  defp get_module_doc(mod) do
    case Code.fetch_docs(mod) do
      {:docs_v1, _, _, "text/markdown", %{"en" => doc}, _, _} ->
        # Extract first sentence or strip newlines
        doc |> String.split("\n") |> List.first() |> String.slice(0, 50)
      _ ->
        "No documentation available."
    end
  end
end
