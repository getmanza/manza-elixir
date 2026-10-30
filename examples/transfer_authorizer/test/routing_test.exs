defmodule TransferAuthorizer.RoutingTest do
  use ExUnit.Case, async: true

  alias TransferAuthorizer.Routing

  test "says the challenge went to the authorizer when it is pending" do
    assert Routing.describe(%{"status" => "pending"}) =~ "challenge sent"
  end

  test "explains every create-time refusal reason in words" do
    expected = %{
      "untrusted_payee" => "bank details are not trusted",
      "unrestricted_api_key" => "key A has no IP allowlist",
      "over_new_payee_limit" => "limit per transfer to a new payee",
      "over_transfer_limit" => "over the limit per transfer",
      "over_daily_limit" => "limit per 24 hours",
      "currency_mismatch" => "not the enrolled currency",
      "suspended" => "is suspended",
      "secret_expired" => "secret has expired"
    }

    assert Enum.sort(Map.keys(Routing.refusal_reasons())) == Enum.sort(Map.keys(expected))

    for {reason, words} <- expected do
      line = Routing.describe(%{"status" => "refused", "refusal_reason" => reason})

      for part <- ["approvers", "refused", reason, words], do: assert(line =~ part)
    end
  end

  test "points at the docs for a reason it does not know" do
    line = Routing.describe(%{"status" => "refused", "refusal_reason" => "something_new"})

    assert line =~ "something_new"
    assert line =~ "transfer authorization docs"
  end

  test "says no authorizer was enrolled when there is no authorization" do
    assert Routing.describe(nil) =~ "no transfer authorizer"
  end
end
