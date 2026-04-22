# frozen_string_literal: true

require "test_helper"

class CostTest < ActiveSupport::TestCase
  # --- Factories ------------------------------------------------------------

  test "Cost.credits carries the credit amount" do
    cost = Cost.credits(2)
    assert_equal :credits, cost.kind
    assert_equal 2, cost.credits
  end

  test "Cost.deferred has no credit amount" do
    cost = Cost.deferred
    assert_equal :deferred, cost.kind
    assert_nil cost.credits
  end

  test "Cost.none is zero credits" do
    cost = Cost.none
    assert_equal :none, cost.kind
    assert_equal 0, cost.credits
  end

  # --- deferred? ------------------------------------------------------------

  test "deferred? is true only for Cost.deferred" do
    assert_predicate Cost.deferred, :deferred?
    refute_predicate Cost.credits(1), :deferred?
    refute_predicate Cost.none, :deferred?
  end

  # --- sufficient_for? ------------------------------------------------------

  test "Cost.deferred is sufficient for any balance" do
    assert Cost.deferred.sufficient_for?(0)
    assert Cost.deferred.sufficient_for?(100)
  end

  test "Cost.none is sufficient for any balance" do
    assert Cost.none.sufficient_for?(0)
    assert Cost.none.sufficient_for?(100)
  end

  test "Cost.credits requires balance greater than or equal to credits" do
    assert Cost.credits(1).sufficient_for?(1)
    assert Cost.credits(1).sufficient_for?(5)
    refute Cost.credits(2).sufficient_for?(1)
    refute Cost.credits(1).sufficient_for?(0)
  end

  # --- Equality -------------------------------------------------------------

  test "equal kind and credits are ==" do
    assert_equal Cost.credits(2), Cost.credits(2)
    assert_equal Cost.deferred, Cost.deferred
    assert_equal Cost.none, Cost.none
  end

  test "different kind or credits are not ==" do
    refute_equal Cost.credits(1), Cost.credits(2)
    refute_equal Cost.credits(0), Cost.none
    refute_equal Cost.deferred, Cost.none
  end

  test "Cost is not equal to primitives" do
    refute_equal Cost.credits(2), 2
    refute_equal Cost.none, 0
    refute_equal Cost.deferred, nil
  end

  # --- Immutability ---------------------------------------------------------

  test "instances are frozen" do
    assert_predicate Cost.credits(1), :frozen?
    assert_predicate Cost.deferred, :frozen?
    assert_predicate Cost.none, :frozen?
  end
end
