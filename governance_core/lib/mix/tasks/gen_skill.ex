defmodule Mix.Tasks.GenSkill do
  use Mix.Task

  @shortdoc "Appends a new skill/tool entry to SKILL.md"
  @moduledoc """
  Appends a new entry to `SKILL.md` with YAML frontmatter.
  Enforces a 1024-character limit per entry.

  ## Example

      mix gen_skill "My Tool" "A brief description of what it does."
  """

  @skill_file "SKILL.md"

  @impl Mix.Task
  def run([name, description | _]) do
    entry = """
    ---
    name: #{name}
    date: #{Date.to_string(Date.utc_today())}
    ---
    #{description}
    """

    if String.length(entry) > 1024 do
      Mix.raise("Error: Skill entry exceeds 1024 characters limit.")
    else
      File.write!(@skill_file, "\n" <> entry, [:append])
      Mix.shell().info("Successfully appended to #{@skill_file}")
    end
  end

  def run(_) do
    Mix.raise("Usage: mix gen_skill <name> <description>")
  end
end
