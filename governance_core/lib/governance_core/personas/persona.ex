defmodule GovernanceCore.Personas.Persona do
  @moduledoc """
  Schema for the Identity Passport (Humans and Bots).
  Supports the 'Plug-and-Play' swarm architecture with hardware specs,
  karma (trust_score), and channel-specific metadata.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "personas" do
    field(:name, :string)
    field(:role, :string)
    field(:type, :string, default: "picoclaw") # picolaw, agentzero, human_admin, etc.
    
    # IDENTITY PASSPORT & SWARM FIELDS
    field(:sub_type, :string, default: "bot") # bot, human
    field(:access_group, :string, default: "external") # internal (Harezm), external (Marketplace)
    field(:balance_cents, :integer, default: 0) # x402 protocol precision
    field(:metadata, :map, default: %{}) # Hardware specs (gpu, ram), channel IDs (telegram_id)

    field(:skills, {:array, :string}, default: [])
    field(:category, :string)
    field(:description, :string)
    field(:protocol, :string, default: "ABL.ONE/1.0")

    field(:trust_score, :integer, default: 100)
    field(:status, :string, default: "active") # active, paused, safety_shutdown, error

    field(:daily_token_limit, :integer, default: 100_000)
    field(:tokens_used_today, :integer, default: 0)
    field(:memory_limit_mb, :integer, default: 128)
    field(:cpu_limit, :float, default: 0.5)

    field(:price_monthly, :integer, default: 0)
    field(:owner, :string, default: "anonymous")

    # OPERATIONAL STATS
    field(:uptime, :string, default: "100%")
    field(:tasks_done, :integer, default: 0)
    field(:last_seen, :naive_datetime)
    field(:logs, {:array, :string}, default: [])

    timestamps()
  end

  @doc false
  def changeset(persona, attrs) do
    persona
    |> cast(attrs, [:name, :role, :type, :sub_type, :access_group, :balance_cents, :status, :trust_score, :description, :category, :skills, :metadata])
    |> validate_required([:name, :sub_type, :access_group, :status])
    |> validate_inclusion(:sub_type, ["bot", "human"])
    |> validate_inclusion(:access_group, ["internal", "external"])
    |> validate_number(:trust_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
