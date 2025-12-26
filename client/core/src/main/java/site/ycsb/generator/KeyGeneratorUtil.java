package site.ycsb.generator;

import java.util.concurrent.ThreadLocalRandom;

public class KeyGeneratorUtil {

    /**
     * Generates a random key ID based on the configured distribution.
     * Mimics the C++ GetRandomKey function from RocksDB db_bench_tool.
     *
     * @param readRandomExpRange Parameter controlling the distribution.
     *                           0.0 means uniform distribution.
     *                           A positive value introduces exponential distribution.
     * @param numKeys            The total number of keys (upper bound for the modulo operation).
     *                           Must be positive.
     * @return A random key ID (long) between 0 and numKeys-1.
     */
    public static long getRandomKey(double readRandomExpRange, long numKeys) {
        if (numKeys <= 0) {
            throw new IllegalArgumentException("numKeys must be positive.");
        }

        // Get a random 64-bit integer.
        long randInt = Math.abs(ThreadLocalRandom.current().nextLong());
        long keyRand;

        if (readRandomExpRange == 0.0) {
            // Uniform distribution: rand_int % numKeys
            // Use Math.abs to ensure the result of modulo is non-negative.
            keyRand = Math.abs(randInt) % numKeys;
        } else {
            // Exponential distribution followed by hashing to avoid locality.
            final long kBigInt = 1L << 62;
            // Ensure non-negative before modulo kBigInt
            long randForExp = Math.abs(randInt) % kBigInt;

            // Calculate the exponent based on the random number and range.
            double order = -((double) randForExp / (double) kBigInt) * readRandomExpRange;
            // Calculate the exponential random factor.
            double expRan = Math.exp(order);

            // Scale by the number of keys. Potential overflow mimics C++ behavior.
            long randNum = (long) (expRan * (double) numKeys);

            // Apply a prime multiplier to map to a different number, avoiding locality.
            final long kBigPrime = 0x5bd1e995L;

            // Multiplication might overflow, which is acceptable per C++ comments.
            // Use Math.abs before the final modulo numKeys.
            keyRand = Math.abs(randNum * kBigPrime) % numKeys;
        }
        return keyRand;
    }

    // Example usage:
    public static void main(String[] args) {
        long totalKeys = 1000000L;

        System.out.println("Generating 10 random keys (Uniform Distribution):");
        for (int i = 0; i < 10; i++) {
            System.out.println(getRandomKey(0.0, totalKeys));
        }

        System.out.println("\nGenerating 10 random keys (Exponential Distribution, Range = 5.0):");
        for (int i = 0; i < 10; i++) {
            System.out.println(getRandomKey(5.0, totalKeys));
        }
    }
}