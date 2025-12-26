/**
 * Copyright (c) 2010-2016 Yahoo! Inc., 2017 YCSB contributors. All rights reserved.
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

import java.util.ArrayList;
import java.util.List;
import java.util.Random;
import java.util.concurrent.ThreadLocalRandom;

/**
 * A generator of a zipfian distribution. It produces a sequence of items, such that some items are more popular than
 * others, according to a zipfian distribution. When you construct an instance of this class, you specify the number
 * of items in the set to draw from, either by specifying an itemcount (so that the sequence is of items from 0 to
 * itemcount-1) or by specifying a min and a max (so that the sequence is of items from min to max inclusive). After
 * you construct the instance, you can change the number of items by calling nextInt(itemcount) or nextLong(itemcount).
 * <p>
 * Unlike @ZipfianGenerator, this class scatters the "popular" items across the itemspace. Use this, instead of
 * @ZipfianGenerator, if you don't want the head of the distribution (the popular items) clustered together.
 */
public class MixgraphGenerator extends NumberGenerator {
  // public static final double ZETAN = 26.46902820178302;
  // public static final double USED_ZIPFIAN_CONSTANT = 0.99;
  // public static final long ITEM_COUNT = 10000000000L;

  // private ZipfianGenerator gen;
  private final long min, max, itemcount;


  // Define the keyrange unit
  public class KeyRangeUnit {
    long keyrange_start;
    long keyrange_access;
    long keyrange_keys;
  }

  /**
   * parameters for the mixgraph generator
   * The probability density function for keyrange access distribution is: f(x) = ax^b+cx^d
   */
  private static final double KEYRANGE_DIST_A = 14.18;
  private static final double KEYRANGE_DIST_B = -2.917;
  private static final double KEYRANGE_DIST_C = 0.0164;
  private static final double KEYRANGE_DIST_D = -0.08082;
  private static int MAX_SSTABLE_NUM = 10000000; // Based on the FAST'20 paper
  private static long KEYRANGE_SIZE = 0;
  private static long KEYRANGE_RAND_MAX = 0;
  private List<KeyRangeUnit> keyrange_set_ = new ArrayList<>();

  private static final double KEY_DIST_A = 0;
  private static final double KEY_DIST_B = 0;
  private static final double KEY_DIST_C = 0;
  

  /******************************* Constructors **************************************/

  /**
   * Create the mixgraph generator for the specified number of items and several parameters.
   *
   * @param items The number of items in the distribution.
   */
  public MixgraphGenerator(long items) {
    this.min = 0;
    this.max = items - 1;
    this.itemcount = items;

    long amplify = 0;
    long keyrange_start = 0;

    if (MAX_SSTABLE_NUM <= 0) {
      MAX_SSTABLE_NUM = 1;
    }
    KEYRANGE_SIZE = itemcount / MAX_SSTABLE_NUM;

    // Calculate the key-range shares size based on the input parameters
    for (long pfx = MAX_SSTABLE_NUM; pfx >= 1; pfx--) {
      // Step 1. Calculate the probability that this key range will be
      // accessed in a query. It is based on the two-term expoential
      // distribution

      double keyrange_p = KEYRANGE_DIST_A * Math.pow(pfx, KEYRANGE_DIST_B) +
              KEYRANGE_DIST_C * Math.pow(pfx, KEYRANGE_DIST_D);
      if (keyrange_p < Math.pow(10.0, -16.0)) {
        keyrange_p = 0.0;
      }


      // Step 2. Calculate the amplify
      // In order to allocate a query to a key-range based on the random
      // number generated for this query, we need to extend the probability
      // of each key range from [0,1] to [0, amplify]. Amplify is calculated
      // by 1/(smallest key-range probability). In this way, we ensure that
      // all key-ranges are assigned with an Integer that  >=0
      if (amplify == 0 && keyrange_p > 0) {
        amplify = (long) Math.floor(1 / keyrange_p) + 1;
      }

      // Step 3. For each key-range, we calculate its position in the
      // [0, amplify] range, including the start, the size (keyrange_access)
      // KeyrangeUnit p_unit;
      KeyRangeUnit p_unit = new KeyRangeUnit();
      p_unit.keyrange_start = keyrange_start;
      if (0.0 >= keyrange_p) {
        p_unit.keyrange_access = 0;
      } else {
        p_unit.keyrange_access = (long) Math.floor(amplify * keyrange_p);
      }
      p_unit.keyrange_keys = KEYRANGE_SIZE;
      // keyrange_set_.push_back(p_unit);
      keyrange_set_.add(p_unit);
      keyrange_start += p_unit.keyrange_access;
    }
    KEYRANGE_RAND_MAX = keyrange_start;

    // Step 4. Shuffle the key-ranges randomly
    // Since the access probability is calculated from small to large,
    // If we do not re-allocate them, hot key-ranges are always at the end
    // and cold key-ranges are at the begin of the key space. Therefore, the
    // key-ranges are shuffled and the rand seed is only decide by the
    // key-range hotness distribution. With the same distribution parameters
    // the shuffle results are the same.
    Random rand_loca = new Random(KEYRANGE_RAND_MAX);

    for (int i = 0; i < MAX_SSTABLE_NUM; i++) {
      int pos = rand_loca.nextInt(MAX_SSTABLE_NUM);
      assert (i >= 0 && i < keyrange_set_.size() && pos >= 0 && pos < keyrange_set_.size());
      KeyRangeUnit temp = keyrange_set_.get(i);
      // System.out.println("i: " + i + " pos: " + pos + " temp: " + temp.keyrange_access);
      keyrange_set_.set(i, keyrange_set_.get(pos));
      keyrange_set_.set(pos, temp);
    }

    // Step 5. Recalculate the prefix start postion after shuffling
    long offset = 0;
    for (int i = 0; i < keyrange_set_.size(); i++) {
      KeyRangeUnit p_unit = keyrange_set_.get(i);
      p_unit.keyrange_start = offset;
      offset += p_unit.keyrange_access;
    }
  }

  /**************************************************************************************************/

  /**
   * Return the next long in the sequence.
   * rewrite the function of long DistGetKeyID() in db_bench_tool.cc 
   */
  @Override
  public Long nextValue() {
    long ret = 0;

    long init_rand = ThreadLocalRandom.current().nextLong(KEYRANGE_RAND_MAX);
    // long keyrange_rand = init_rand % KEYRANGE_RAND_MAX;

    // calculate and select one key-range that contains the new key
    long start = 0, end = keyrange_set_.size();
    while (start + 1 < end) {
      long mid = start + (end - start) / 2;
      assert (mid >= 0 && mid < keyrange_set_.size());
      if (init_rand < keyrange_set_.get((int) mid).keyrange_start) {
        end = mid;
      } else {
        start = mid;
      }
    }
    long keyrange_id = start;

    // Select one key in the key-range and compose the keyID
    long key_offset = 0, key_seed;
    // if (KEY_DIST_A == 0.0 || KEY_DIST_B == 0.0) {
    key_offset = init_rand % KEYRANGE_SIZE;
    // } else {
    //   double u = (double) (init_rand % keyrange_set_.get((int) keyrange_id).keyrange_keys) /
    //           keyrange_set_.get((int) keyrange_id).keyrange_keys;
    //   key_seed = (long) Math.ceil(Math.pow((u / KEY_DIST_A), (1 / KEY_DIST_B)));
    //   Random rand_key = new Random(key_seed);
    //   key_offset = rand_key.nextLong() % keyrange_set_.get((int) keyrange_id).keyrange_keys;
    // }
    // if (keyrange_id < 0 || key_offset < 0) {
    //   System.out.println("keyrange_id: " + keyrange_id + " key_offset: " + key_offset);
    // }
    // System.out.println("keyrange_id: " + keyrange_id);

    ret = KEYRANGE_SIZE * keyrange_id + key_offset;
    return ret;
  }

  public static void main(String[] args) {
    MixgraphGenerator gen = new MixgraphGenerator(100000000);

    for (int i = 0; i < 10000; i++) {
      System.out.println("" + gen.nextValue());
    }
  }

  /**
   * since the values are scrambled (hopefully uniformly), the mean is simply the middle of the range.
   */
  @Override
  public double mean() {
    return ((min) + max) / 2.0;
  }
}
