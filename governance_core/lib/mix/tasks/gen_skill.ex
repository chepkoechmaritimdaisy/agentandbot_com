defmodule Mix.Tasks.GenSkill do
  use Mix.Task

  @shortdoc "Generates or updates SKILL.md documentation for an agent tool"
  @moduledoc """
  Generates a standard SKILL.md file for a given agent or tool.
  Ensures the content is within the 1024 character limit and follows the YAML frontmatter standard.

  ## Usage

      mix gen_skill <agent_name>

  Example:

      mix gen_skill agentandbot-payment

  This will create `.agent/skills/agentandbot-payment/SKILL.md`.
  """

  @limit 1024

  def run(args) do
    case args do
      [name] ->
        generate_skill(name)

      _ ->
        Mix.raise("Usage: mix gen_skill <agent_name>")
    end
  end

  defp generate_skill(name) do
    base_path = Path.join([".agent", "skills", name])
    file_path = Path.join(base_path, "SKILL.md")

    File.mkdir_p!(base_path)

    if File.exists?(file_path) do
      Mix.shell().info("Checking existing SKILL.md for #{name}...")
      validate_skill(file_path)
    else
      create_skill(name, file_path)
    end
  end

  defp create_skill(name, path) do
    content = """
---
name: #{name}
description: >
  Short description of #{name}.
  Keep it under 1024 chars.
---

# #{String.capitalize(name)} Skill

Describe what this agent/tool does here.

## Usage

Provide usage examples.

## Inputs

- input1: Description
- input2: Description

## Outputs

- output1: Description
"""
    File.write!(path, content)
    Mix.shell().info("Created #{path}")
    validate_skill(path)
  end

  defp validate_skill(path) do
    content = File.read!(path)
    length = String.length(content)

    if length > @limit do
      Mix.shell().error("WARNING: #{path} is too long! (#{length} chars). Limit is #{@limit}.")
    else
      Mix.shell().info("✓ #{path} is valid (#{length}/#{@limit} chars).")
    end

    if not String.starts_with?(content, "---") do
      Mix.shell().error("WARNING: #{path} does not start with YAML frontmatter (---).")
    end
  end
end
