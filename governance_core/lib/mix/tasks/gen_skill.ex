defmodule Mix.Tasks.GenSkill do
  @moduledoc """
  Generates or appends to a SKILL.md file for a given agent/skill name.
  Adheres to the 1024-character limit.

  Usage:
      mix gen_skill <skill_name> "<description>" "<version>"
  """
  use Mix.Task
  require Logger

  @max_chars 1024

  @shortdoc "Generates a SKILL.md file"
  def run([name, description | rest]) do
    version = Enum.at(rest, 0, "1.0.0")

    dir_path = ".agent/skills/#{name}"
    file_path = "#{dir_path}/SKILL.md"

    File.mkdir_p!(dir_path)

    yaml_frontmatter = """
    ---
    name: #{name}
    description: #{description}
    version: #{version}
    ---
    """

    content = """
    #{yaml_frontmatter}
    # #{name}

    #{description}
    """

    if String.length(content) > @max_chars do
      Logger.error("SKILL.md content exceeds 1024 characters limit! (Current: #{String.length(content)})")
      System.halt(1)
    else
      File.write!(file_path, content)
      Logger.info("Created #{file_path} successfully.")
    end
  end

  def run(_) do
    Logger.error("Usage: mix gen_skill <skill_name> \"<description>\" [version]")
    System.halt(1)
  end
end
