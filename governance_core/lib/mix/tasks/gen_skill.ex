defmodule Mix.Tasks.GenSkill do
  @moduledoc """
  Generates a SKILL.md file adhering to the project's standard 1024-character limit
  with YAML frontmatter.

  Usage:
      mix gen_skill <tool_name> <description>

  Example:
      mix gen_skill "Read API" "Reads API endpoints for given module."
  """
  use Mix.Task

  @shortdoc "Generates a SKILL.md file"

  @impl Mix.Task
  def run([tool_name, description]) do
    content = """
    ---
    name: #{tool_name}
    version: 1.0.0
    ---

    # #{tool_name}

    #{description}
    """

    # Ensure it's within the 1024 char limit
    if String.length(content) > 1024 do
      Mix.shell().error("Error: Description makes the content exceed the 1024 character limit.")
    else
      File.mkdir_p!(".agent/skills")
      skill_dir = ".agent/skills/agentandbot-#{String.downcase(String.replace(tool_name, " ", "-"))}"
      File.mkdir_p!(skill_dir)

      file_path = Path.join(skill_dir, "SKILL.md")

      File.write!(file_path, content)
      Mix.shell().info("Generated SKILL.md for #{tool_name} at #{file_path}")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix gen_skill <tool_name> <description>")
  end
end
