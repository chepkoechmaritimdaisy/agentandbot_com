defmodule Mix.Tasks.GenSkill do
  use Mix.Task

  @shortdoc "Generates and appends a new SKILL.md entry."

  @moduledoc """
  Generates and appends a new SKILL.md entry following standards.
  Usage: mix gen_skill <tool_name> <description>
  """

  def run(args) do
    case args do
      [tool_name | description_parts] ->
        description = Enum.join(description_parts, " ")
        append_to_skill_md(tool_name, description)

      _ ->
        Mix.shell().error("Usage: mix gen_skill <tool_name> <description>")
    end
  end

  defp append_to_skill_md(tool_name, description) do
    entry = """
    ---
    name: #{tool_name}
    created_at: #{DateTime.utc_now() |> DateTime.to_iso8601()}
    ---
    # #{tool_name}

    #{description}
    """

    # Enforce 1024 character limit
    truncated_entry =
      if String.length(entry) > 1024 do
        String.slice(entry, 0, 1021) <> "..."
      else
        entry
      end

    file_path = "SKILL.md"

    # Ensure there's a newline between entries if file exists
    content_to_write =
      if File.exists?(file_path) do
        "\n" <> truncated_entry
      else
        truncated_entry
      end

    File.write!(file_path, content_to_write, [:append])
    Mix.shell().info("Successfully added #{tool_name} to #{file_path}")
  end
end
