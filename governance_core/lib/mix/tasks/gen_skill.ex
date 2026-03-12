defmodule Mix.Tasks.GenSkill do
  @moduledoc """
  Standardizes and appends tool documentation to SKILL.md.
  Ensures the entry follows YAML frontmatter standards and does not exceed 1024 characters.

  Usage:
      mix gen_skill "ToolName" "Description of what it does" "How to use it"
  """
  use Mix.Task

  @shortdoc "Appends a new tool entry to SKILL.md"

  @skill_file "SKILL.md"
  @max_chars 1024

  @impl Mix.Task
  def run(args) do
    case args do
      [name, desc, usage] ->
        entry = generate_entry(name, desc, usage)

        if String.length(entry) > @max_chars do
          Mix.shell().error("Entry exceeds maximum allowed length of #{@max_chars} characters.")
        else
          append_to_skill_md(entry)
          Mix.shell().info("Successfully added #{name} to #{@skill_file}")
        end

      _ ->
        Mix.shell().error("Usage: mix gen_skill \"Name\" \"Description\" \"Usage\"")
    end
  end

  defp generate_entry(name, desc, usage) do
    """
    ---
    tool: #{name}
    type: custom
    ---
    # #{name}
    **Description**: #{desc}
    **Usage**: #{usage}
    """
  end

  defp append_to_skill_md(entry) do
    # Ensure the file exists
    if not File.exists?(@skill_file) do
      File.write!(@skill_file, "# Project Skills & Tools\n\n")
    end

    File.write!(@skill_file, "\n" <> entry, [:append])
  end
end
