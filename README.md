# Optix

## Overview

**Optix** is a decentralized options trading platform on the Stacks blockchain. It enables users to write, buy, exercise, and trade options for STX and other supported assets. The contract facilitates automated collateral management, price validation through oracles, and settlement of profit or loss directly on-chain.

## Key Features

* **Options Creation:** Writers can create call or put options with configurable strike price, premium, and expiry.
* **Collateral Locking:** Ensures adequate collateral is held for every written option.
* **Option Trading:** Buyers can purchase options from writers or resell active options to other users.
* **Automated Settlement:** Profits and losses are calculated and distributed upon exercise or expiry.
* **Price Oracle Integration:** Uses an oracle for asset price validation at exercise.
* **Market Data Tracking:** Records real-time asset prices and exercise histories for transparency.
* **Risk Management:** Includes functions for early position closing and collateral release after expiry.

## Core Contract Components

### 1. Constants

Defines identifiers for option types (`OPTION-CALL`, `OPTION-PUT`), status codes (`OPTION-ACTIVE`, `OPTION-EXERCISED`, `OPTION-EXPIRED`), and error codes for transaction validation.

### 2. Data Variables

* **`option-counter`** – Tracks total number of options created.
* **`oracle`** – Stores the principal address responsible for updating market prices.

### 3. Data Maps

* **`options`** – Holds full option metadata such as writer, holder, type, strike price, premium, expiry, and status.
* **`option-collateral`** – Tracks locked collateral amounts and release status.
* **`user-positions`** – Records user positions, whether long or short, with entry prices.
* **`market-prices`** – Stores price data for each asset as updated by the oracle.
* **`exercise-history`** – Logs details of exercised options including profit and execution block.

### 4. Main Functions

#### Option Lifecycle

* **`write-option`** – Creates a new option and locks collateral from the writer.
* **`buy-option`** – Transfers ownership of an option to the buyer upon payment of the premium.
* **`exercise-option`** – Allows the holder to exercise if profitable based on current price.
* **`expire-option`** – Releases collateral and marks an option as expired when past expiry.
* **`close-position`** – Enables the holder to sell an active option to another buyer before expiry.

#### Market and Oracle

* **`update-price`** – Updates the market price of an asset (oracle-only).
* **`set-oracle`** – Assigns a new oracle for price updates.

#### Analytics and Computation

* **`calculate-option-value`** – Estimates an option’s theoretical value using a simplified Black-Scholes model.
* **`calculate-payoff`** – Computes net profit or loss for a given option based on current market price.
* **`is-option-in-money`** – Checks whether an option is currently profitable.
* **`get-time-to-expiry`** – Returns remaining blocks before expiry.

### 5. Read-Only Queries

* **`get-option`** – Fetches complete data of an option.
* **`get-option-collateral`** – Returns collateral details for an option.
* **`get-user-position`** – Retrieves position data for a specific user and option.
* **`get-market-price`** – Displays current market price for an asset.
* **`get-exercise-history`** – Provides record of an exercised option.
* **`get-option-count`** – Returns total number of options written.
* **`get-oracle`** – Displays the current oracle address.

## Validation and Security

* **Authorization Checks:** Only the oracle can update prices or confirm price data during exercise.
* **Collateral Verification:** Ensures writers possess sufficient collateral before creating options.
* **Profit Validation:** Prevents ineligible or expired options from being exercised.
* **Error Handling:** Returns structured error codes for every invalid transaction scenario.

## Workflow Summary

1. **Writer creates** an option using `write-option`, locking collateral.
2. **Buyer purchases** the option with `buy-option`, paying a premium.
3. **Holder exercises** the option before expiry if profitable, triggering on-chain settlement.
4. **Expired options** can be closed to release collateral using `expire-option`.
5. **Market data** and **option metrics** are continuously updated through the oracle and read-only functions.

## Summary

**Optix** brings transparent and automated options trading to the blockchain, eliminating intermediaries through smart contract-enforced settlement and price validation. It provides a complete ecosystem for creating, trading, and exercising options while ensuring fairness, security, and efficiency.
