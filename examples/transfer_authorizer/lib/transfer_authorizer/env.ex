defmodule TransferAuthorizer.Env do
  @moduledoc """
  Loads `KEY=value` lines from a `.env` file into the environment,
  overriding what is already set (a stale exported variable never wins).
  Blank lines and `#` comments are skipped; surrounding quotes are dropped.
  """

  def overload(path) do
    case File.read(path) do
      {:ok, contents} ->
        for line <- String.split(contents, ~r/\R/),
            line = String.trim(line),
            line != "" and not String.starts_with?(line, "#"),
            [key, value] <- [String.split(line, "=", parts: 2)] do
          System.put_env(
            String.trim(key),
            value |> String.trim() |> String.trim("\"") |> String.trim("'")
          )
        end

        :ok

      {:error, :enoent} ->
        :ok
    end
  end
end
