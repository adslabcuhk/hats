package org.iq80.twoLayerLog;

import java.io.File;
import java.io.Serializable;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

import org.iq80.twoLayerLog.impl.TableCache;
import org.iq80.twoLayerLog.impl.VersionSet;
import org.iq80.twoLayerLog.impl.WriteBatchImpl;
import org.iq80.twoLayerLog.util.Slice;

public class DBMeta implements Serializable
{
    // TODO: We need to open these two parameters instead of serializing them
    public Map<String, TableCache> groupTableCacheMap; // Map<rangGroupID, rangeGroupFile>
    public Map<String, VersionSet> groupVersionSetMap; // 
    public Map<String, File> groupIdFileMap; // Map<rangGroupID, rangeGroupFile>

    // public Map<String,WriteBatchImpl> writeBatchMap;
    public Map<Integer,File> replicasDirMap; 
    public Map<String,Integer> grouptoIDMap;
    // public Map<Integer,List<String>> rangeUpperBoundMap;
	public Map<String,Integer> continueWriteGroupMap;
    public Map<Integer, Slice> tableMetaMap;

    public DBMeta()
    {
        // this.groupTableCacheMap = new HashMap<String, TableCache>();
        // this.groupVersionSetMap = new HashMap<String, VersionSet>();
        // this.writeBatchMap = new HashMap<String, WriteBatchImpl>();
        this.groupIdFileMap = new HashMap<String, File>();
        this.replicasDirMap = new HashMap<Integer, File>();
        this.grouptoIDMap = new HashMap<String, Integer>();
        // this.rangeUpperBoundMap = new HashMap<Integer, List<String>>();
        this.continueWriteGroupMap = new HashMap<String, Integer>();
        this.tableMetaMap = new HashMap<Integer, Slice>();
    }

}
