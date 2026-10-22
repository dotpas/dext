/**
 * GTest smoke cases for Test Explorer (not MainSource — opens as a normal unit).
 */

#include "DextGTestAdapter.hpp"

TEST(SmokeSuite, OnePlusOne)
{
  EXPECT_EQ(2, 1 + 1);
}

TEST(SmokeSuite, IntentionalFail)
{
  EXPECT_EQ(2, 1 + 2) << "intentional fail for Explorer smoke";
}
