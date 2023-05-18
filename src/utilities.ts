import BN from 'bn.js'
import { BigNumber, utils, FixedNumber } from 'ethers';
import { CurrencyAmount, Fraction, Percent, Price, Token } from '@uniswap/sdk-core'
import { FeeAmount, priceToClosestTick, TickMath } from '@uniswap/v3-sdk';
import JSBI from 'jsbi';

export async function getPriceBits(prices: string[]): Promise<string> {
  if (prices.length > 8) {
    throw new Error("max prices.length exceeded")
  }

  let priceBits = new BN('0')

  for (let j = 0; j < 8; j++) {
    let index = j
    if (index >= prices.length) {
      break
    }

    const price = new BN(prices[index])
    if (price.gt(new BN("2147483648"))) { // 2^31
      throw new Error(`price exceeds bit limit ${price.toString()}`)
    }

    priceBits = priceBits.or(price.shln(j * 32))
  }

  return priceBits.toString()
}

export function ethUsdcPriceToSqrtPriceX962(price: Price<Token, Token>): string {
  const tick = priceToClosestTick(price);
  console.log('tick:', tick);
  const sqrtPriceX96 = TickMath.getSqrtRatioAtTick(tick);

  console.log('price to tick:', priceToTick(price));

  console.log('tick con:', TickMath.getSqrtRatioAtTick(-201057).toString());
  return sqrtPriceX96.toString();
}


export function ethUsdcPriceToSqrtPriceX96(price: string): string {

  // Convert the price to a BigNumber with 18 decimal places
  const priceInWei = utils.parseUnits(price, 18);

  // Convert the priceInWei to a BN instance
  const priceInWeiBN = new BN(priceInWei.toString());

  // Multiply the price by 2^96 to adjust for the x96 format
  const priceX96 = priceInWeiBN.mul(new BN(2).pow(new BN(96)));

  // Calculate the square root of the price
  const sqrtPriceX96 = sqrtBN(priceX96);

  return sqrtPriceX96.toString();
}

function sqrtBN(value: BN): BN {
  if (value.isNeg()) throw new Error('Square root of a negative number is not supported.');

  let x = value.clone();
  let xn = value.addn(1).iushrn(1);

  while (xn.lt(x)) {
    x = xn.clone();
    xn = value.div(x).add(x).iushrn(1);
  }

  return x;
}

export function priceToTick(price: Price<Token, Token>): number {
  const baseCurrency = price.baseCurrency;
  const quoteCurrency = price.quoteCurrency;

  const tokenReverse = baseCurrency.symbol === 'WETH'; // Change 'WETH' to your base token symbol
  const tokenTenBase = baseCurrency.decimals - quoteCurrency.decimals;

  const numerator = FixedNumber.fromValue(BigNumber.from(price.numerator.toString()), price.quoteCurrency.decimals);
  const denominator = FixedNumber.fromValue(BigNumber.from(price.denominator.toString()), price.baseCurrency.decimals);

  let adjustedPrice = numerator.divUnsafe(denominator);
  if (tokenReverse) {
    // adjustedPrice = denominator.divUnsafe(numerator);
  }

  adjustedPrice = adjustedPrice.divUnsafe(FixedNumber.from(Math.pow(10, tokenTenBase)));

  const tick = Math.floor(Math.log(adjustedPrice.toUnsafeFloat()) / Math.log(1.0001));
  return tick;
}