package org.iq80.twoLayerLog.util;

import java.io.Serializable;
import java.util.Comparator;

public final class SliceComparator
        implements Comparator<Slice>, Serializable
{
    public static final SliceComparator SLICE_COMPARATOR = new SliceComparator();

    @Override
    public int compare(Slice sliceA, Slice sliceB)
    {
        return sliceA.compareTo(sliceB);
    }
}
