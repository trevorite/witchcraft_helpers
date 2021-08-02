defmodule MagicWand.InOut do
  @moduledoc false

  defstruct input: %{}, output: []

  def new(%{} = input) do
    %__MODULE__{input: input, output: []}
  end
end