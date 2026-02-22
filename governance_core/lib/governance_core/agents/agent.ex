defmodule GovernanceCore.Agents.Agent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "agents" do
    field :name, :string
    field :trust_score, :integer, default: 100
    field :status, :string, default: "active" # active, paused, safety_shutdown

    timestamps()
  end

  @doc false
  def changeset(agent, attrs) do
    agent
    |> cast(attrs, [:name, :trust_score, :status])
    |> validate_required([:name, :trust_score, :status])
    |> validate_number(:trust_score, greater_than_or_equal_to: 0, less_than_or_equal_to: 100)
  end
end
