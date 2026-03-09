defmodule Mix.Tasks.GenSkill do
  @shortdoc "Generates or updates a SKILL.md file for a tool"
  @moduledoc """
  Generates or updates a SKILL.md documentation file for a given tool.
  Enforces a 1024-character limit per entry and uses YAML frontmatter.

  Usage:
      mix gen_skill "Tool Name" "Description of the tool"
  """
  use Mix.Task

  @impl Mix.Task
  def run([name, description]) do
    skill_dir = ".agent/skills/agentandbot-#{slugify(name)}"
    File.mkdir_p!(skill_dir)
    skill_file = Path.join(skill_dir, "SKILL.md")

    yaml_frontmatter = """
    ---
    name: agentandbot-#{slugify(name)}
    description: >
      #{String.replace(description, "\n", "\n  ")}
    ---
    """

    content = """
    #{yaml_frontmatter}

    # Agentandbot — #{name} Integration

    #{description}
    """

    if String.length(content) > 1024 do
      Mix.shell().error("Error: SKILL.md content exceeds 1024 characters (#{String.length(content)}). Please shorten the description.")
    else
      File.write!(skill_file, content)
      Mix.shell().info("Generated #{skill_file} successfully.")
    end
  end

  def run(_) do
    Mix.shell().error("Usage: mix gen_skill \\"Tool Name\\" \\"Description of the tool\\"")
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  end
end
