/**
 * Copyright (c) 2010 Yahoo! Inc. Copyright (c) 2017 YCSB contributors. All rights reserved.
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

package site.ycsb.generator;

import java.util.concurrent.ThreadLocalRandom;

/**
 * Generates longs randomly uniform from an interval.
 */
public class ParetoLongGenerator extends NumberGenerator {
  private final long lb, ub;
  private final double sigma;
  private final double theta;
  private final double k;

  /**
   * Creates a generator that will return longs uniformly randomly from the 
   * interval [lb,ub] inclusive (that is, lb and ub are possible values)
   * (lb and ub are possible values).
   *
   * @param lb the lower bound (inclusive) of generated values
   * @param ub the upper bound (inclusive) of generated values
   */
  public ParetoLongGenerator(long lb, long ub, double sigma, double theta, double k) {
    this.lb = lb;
    this.ub = ub;
    this.sigma = sigma;
    this.theta = theta;
    this.k = k;

  }

  @Override
  public Long nextValue() {
    // double u = ThreadLocalRandom.current().nextDouble(0, 1);
    double u = ThreadLocalRandom.current().nextDouble(Double.MIN_VALUE, 1.0);
    double paretoValue;
    final double epsilon = 1e-9;
    if (Math.abs(k) < epsilon) {
      paretoValue = theta - sigma * Math.log(u);
    } else {
        paretoValue = theta + sigma * (Math.pow(u, -k) - 1.0) / k;
    }

    if (sigma == 25.45) {
        paretoValue *= 10;
    }

    long result = (long) paretoValue + lb;
    // setLastValue(result);
    result = Math.max(lb, Math.min(ub, result));
    return result;
  }

  public static void main(String[] args) {    
    ParetoLongGenerator gen = new ParetoLongGenerator(500, 1000, 25.45, 0, 0.2615);
    for (int i = 0; i < 1000000; i++) {
      System.out.println(gen.nextValue());
    }
  }

  @Override
  public double mean() {
    return ((lb + (long) ub)) / 2.0;
  }
}
