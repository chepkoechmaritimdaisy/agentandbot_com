defmodule Mix.Tasks.GenSkill do
  @shortdoc "Generates or updates a SKILL.md file adhering to standards"
  @moduledoc """
  A mix task to automatically create or update SKILL.md documentation for tools.
  Ensures the documentation includes YAML frontmatter and does not exceed a 1024-character limit.

  Usage:
      mix gen_skill "Tool Name" "Description of the tool..."
  """
  use Mix.Task

  @max_chars 1024

  @impl Mix.Task
  def run(args) do
    case args do
      [name, description | _] ->
        generate_skill_file(name, description)

      _ ->
        Mix.shell().error("Usage: mix gen_skill <name> <description>")
    end
  end

  defp generate_skill_file(name, description) do
    yaml_frontmatter = """
    ---
    name: #{name}
    type: tool
    version: 1.0.0
    ---
    """

    content = "#{yaml_frontmatter}\n# #{name}\n\n#{description}\n"

    if String.length(content) > @max_chars do
      Mix.shell().error("Error: SKILL.md content exceeds the 1024-character limit (current length: #{String.length(content)}).")
      Mix.shell().info("Please shorten the description.")
    else
      File.write!("SKILL.md", content)
      Mix.shell().info("Successfully generated SKILL.md.")
    end
  end
end
