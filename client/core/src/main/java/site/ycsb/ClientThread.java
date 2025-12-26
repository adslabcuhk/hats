/**
 * Copyright (c) 2010-2016 Yahoo! Inc., 2017 YCSB contributors All rights reserved.
 * <p>
 * Licensed under the Apache License, Version 2.0 (the "License"); you
 * may not use this file except in compliance with the License. You
 * may obtain a copy of the License at
 * <p>
 * http://www.apache.org/licenses/LICENSE-2.0
 * <p>
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied. See the License for the specific language governing
 * permissions and limitations under the License. See accompanying
 * LICENSE file.
 */

package site.ycsb;

import java.util.Properties;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.ThreadLocalRandom;
import java.util.concurrent.locks.LockSupport;

import site.ycsb.measurements.Measurements;

/**
 * A thread for executing transactions or data inserts to the database.
 */
public class ClientThread implements Runnable {
  // Counts down each of the clients completing.
  private final CountDownLatch completeLatch;

  private static boolean spinSleep;
  private DB db;
  private boolean dotransactions;
  private Workload workload;
  private int opcount;
  private double targetOpsPerMs;

  private int opsdone;
  private int threadid;
  private int threadcount;
  private Object workloadstate;
  private Properties props;
  private long targetOpsTickNs;
  private final Measurements measurements;

  
  // --- New variables for dynamic rate limiting ---
  private boolean dynamicRateLimiterEnabled = false;
  private long dynamicRateIntervalNanos = 5000000000L; // 5000ms
  private long lastRateAdjustmentTimeNanos;
  private double sineNoiseFactor = 0;
  // --- End of new variables ---


  /**
   * Constructor.
   *
   * @param db                   the DB implementation to use
   * @param dotransactions       true to do transactions, false to insert data
   * @param workload             the workload to use
   * @param props                the properties defining the experiment
   * @param opcount              the number of operations (transactions or inserts) to do
   * @param targetperthreadperms target number of operations per thread per ms
   * @param completeLatch        The latch tracking the completion of all clients.
   */
  public ClientThread(DB db, boolean dotransactions, Workload workload, Properties props, int opcount,
                      double targetperthreadperms, CountDownLatch completeLatch) {
    this.db = db;
    this.dotransactions = dotransactions;
    this.workload = workload;
    this.opcount = opcount;
    opsdone = 0;
    if (targetperthreadperms > 0) {
      targetOpsPerMs = targetperthreadperms;
      targetOpsTickNs = (long) (1000000 / targetOpsPerMs);
    }
    this.props = props;
    measurements = Measurements.getMeasurements();
    spinSleep = Boolean.valueOf(this.props.getProperty("spin.sleep", "false"));
    this.completeLatch = completeLatch;
  }

  public void setThreadId(final int threadId) {
    threadid = threadId;
  }

  public void setThreadCount(final int threadCount) {
    threadcount = threadCount;
  }

  public int getOpsDone() {
    return opsdone;
  }

  @Override
  public void run() {
    try {
      db.init();
    } catch (DBException e) {
      e.printStackTrace();
      e.printStackTrace(System.out);
      return;
    }

    try {
      workloadstate = workload.initThread(props, threadid, threadcount);
    } catch (WorkloadException e) {
      e.printStackTrace();
      e.printStackTrace(System.out);
      return;
    }

    //NOTE: Switching to using nanoTime and parkNanos for time management here such that the measurements
    // and the client thread have the same view on time.

    //spread the thread operations out so they don't all hit the DB at the same time
    // GH issue 4 - throws exception if _target>1 because random.nextInt argument must be >0
    // and the sleep() doesn't make sense for granularities < 1 ms anyway
    if ((targetOpsPerMs > 0) && (targetOpsPerMs <= 1.0)) {
      long randomMinorDelay = ThreadLocalRandom.current().nextInt((int) targetOpsTickNs);
      sleepUntil(System.nanoTime() + randomMinorDelay);
    }
    try {
      if (dotransactions) {
        long startTimeNanos = System.nanoTime();

        while (((opcount == 0) || (opsdone < opcount)) && !workload.isStopRequested()) {

          if (!workload.doTransaction(db, workloadstate)) {
            break;
          }

          opsdone++;

          // --- Adjust rate dynamically ---
          adjustRateDynamically(startTimeNanos, false);
          // --- End of rate adjustment ---
          throttleNanos(startTimeNanos);
        }
      } else {
        long startTimeNanos = System.nanoTime();

        while (((opcount == 0) || (opsdone < opcount)) && !workload.isStopRequested()) {

          if (!workload.doInsert(db, workloadstate)) {
            break;
          }

          opsdone++;
          // --- Adjust rate dynamically ---
          adjustRateDynamically(startTimeNanos, true);
          // --- End of rate adjustment ---
          throttleNanos(startTimeNanos);
        }
      }
    } catch (Exception e) {
      e.printStackTrace();
      e.printStackTrace(System.out);
      System.exit(0);
    }

    try {
      measurements.setIntendedStartTimeNs(0);
      db.cleanup();
    } catch (DBException e) {
      e.printStackTrace();
      e.printStackTrace(System.out);
    } finally {
      completeLatch.countDown();
    }
  }

  private static void sleepUntil(long deadline) {
    while (System.nanoTime() < deadline) {
      if (!spinSleep) {
        LockSupport.parkNanos(deadline - System.nanoTime());
      }
    }
  }


  private void throttleNanos(long startTimeNanos) {
    //throttle the operations
    if (targetOpsPerMs > 0 && targetOpsTickNs != Long.MAX_VALUE) { // Check if throttling is active
      // delay until next tick
      long deadline = startTimeNanos + opsdone * targetOpsTickNs;
      sleepUntil(deadline);
      measurements.setIntendedStartTimeNs(deadline);
    } else {
       measurements.setIntendedStartTimeNs(0); // No specific intended start time if not throttling
    }
  }

  /**
   * The total amount of work this thread is still expected to do.
   */
  int getOpsTodo() {
    int todo = opcount - opsdone;
    return todo < 0 ? 0 : todo;
  }

  /**
   * Dynamically adjusts the target operations per millisecond based on elapsed time,
   * simulating a sine wave pattern with optional noise, similar to the C++ reference code.
   *
   * @param threadStartTimeNanos The time the main loop of this thread started, in nanoseconds.
   */
  private void adjustRateDynamically(long threadStartTimeNanos, boolean insert) {
    if (!dynamicRateLimiterEnabled) {
      return; // Do nothing if the feature is disabled
    }

    long nowNanos = System.nanoTime();
    long nanosSinceLastAdjustment = nowNanos - lastRateAdjustmentTimeNanos;

    // Check if the adjustment interval has passed
    if (nanosSinceLastAdjustment > dynamicRateIntervalNanos) {
      double nanosSinceStart = (double)(nowNanos - threadStartTimeNanos);
      double secondsSinceStart = nanosSinceStart / 1_000_000_000.0;

      // 1. Calculate the target rate based on the sine wave formula
      double sineRate = calculateSineRate(secondsSinceStart);

      // 2. Add noise to the calculated rate
      double noisyRate = addNoise(sineRate);

      // Ensure rate is not negative
      noisyRate = Math.max(0.0, noisyRate / 1000.0); // Convert to ops/ms

      // 3. Update the thread's target rate
      if (insert) {
        // For inserts, we want to set the target rate directly
        this.targetOpsPerMs = noisyRate * 0.15;
      } else {
        // For transactions, we want to adjust the target rate based on the current rate
        this.targetOpsPerMs = noisyRate * 0.85;
      }
      if (this.targetOpsPerMs > 1e-9) { // Avoid division by zero or near-zero
          this.targetOpsTickNs = (long) (1_000_000.0 / this.targetOpsPerMs);
      } else {
          // If rate is effectively zero, set ticks to max to stop throttling
          this.targetOpsPerMs = 0.0;
          this.targetOpsTickNs = Long.MAX_VALUE;
      }

      // 4. Reset the timer for the next adjustment
      this.lastRateAdjustmentTimeNanos = nowNanos;

    }
  }

  // F(x) = A * sin(B * x + C) + D.
  private double calculateSineRate(double x) {
    return 147.9 * Math.sin(8.3*10e-5 * x) + 50000;
  }

  private double addNoise(double origin) {
    int band_int = 147;
    double delta = (ThreadLocalRandom.current().nextInt(band_int) - band_int / 2) * sineNoiseFactor;
    if (origin + delta < 0) {
      return origin;
    } else {
      return (origin + delta);
    }
  }
}
