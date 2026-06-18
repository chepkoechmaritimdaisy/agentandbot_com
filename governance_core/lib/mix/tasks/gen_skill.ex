defmodule Mix.Tasks.GenSkill do
  @shortdoc "Generates or updates a SKILL.md entry."
  @moduledoc """
  Generates or appends an entry to the SKILL.md file in the project.
  Ensures the skill is documented using YAML frontmatter and limits
  the length of the entry to 1024 characters as per the standards.

  ## Examples

      mix gen_skill "My Tool" "This tool does something awesome."
  """
  use Mix.Task

  @max_length 1024

  @impl Mix.Task
  def run(args) do
    case args do
      [name, description | _] ->
        append_skill(name, description)
      _ ->
        Mix.shell().error("Usage: mix gen_skill <skill_name> <description>")
    end
  end

  defp append_skill(name, description) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

    # YAML frontmatter
    frontmatter = """
    ---
    name: #{name}
    date: #{timestamp}
    ---
    """

    entry = """
    #{frontmatter}
    # #{name}

    #{description}
    """

    # Ensure it's not over 1024 characters
    truncated_entry = if String.length(entry) > @max_length do
      String.slice(entry, 0, @max_length - 3) <> "..."
    else
      entry
    end

    skill_file_path = "SKILL.md"

    # Append to the file (or create if it doesn't exist)
    File.write!(skill_file_path, "\n" <> truncated_entry, [:append])

    Mix.shell().info("Successfully appended skill to #{skill_file_path}")
  end
end
