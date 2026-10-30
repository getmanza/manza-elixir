defmodule TransferAuthorizer.Env do
  @moduledoc """
  Loads `KEY=value` lines from a `.env` file into the environment,
  overriding what is already set (a stale exported variable never wins).
  Blank lines and `#` comments are skipped; a matching pair of surrounding
  quotes is dropped. An unreadable file raises `File.Error`; a missing one is
  skipped.
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
            value |> String.trim() |> unquote_value()
          )
        end

        :ok

      {:error, :enoent} ->
        :ok

      {:error, reason} ->
        raise File.Error, reason: reason, action: "read", path: path
    end
  end

  defp unquote_value(<<quote, rest::binary>> = value) when quote in [?", ?'] do
    if byte_size(rest) > 0 and :binary.last(rest) == quote,
      do: binary_part(rest, 0, byte_size(rest) - 1),
      else: value
  end

  defp unquote_value(value), do: value
end
