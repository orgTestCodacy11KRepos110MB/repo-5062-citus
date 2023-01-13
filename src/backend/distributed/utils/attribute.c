//
// Created by Nils Dijk on 02/12/2022.
//

#include "postgres.h"

#include "distributed/log_utils.h"
#include "distributed/listutils.h"
#include "distributed/tuplestore.h"
#include "executor/execdesc.h"
#include "storage/ipc.h"
#include "storage/shmem.h"
#include "utils/builtins.h"

#include "distributed/utils/attribute.h"

#include <time.h>

static void AttributeMetricsIfApplicable(void);

ExecutorEnd_hook_type prev_ExecutorEnd = NULL;

#define ATTRIBUTE_PREFIX "/* attributeTo: "
#define ATTRIBUTE_STRING_FORMAT "/* attributeTo: %s,%d */"
#define TENANT_MONITOR_COLUMNS 6

/* TODO maybe needs to be a stack */
const char *attributeToTenant = NULL;
CmdType attributeCommandType = CMD_UNKNOWN;
int colocationGroupId = -1;
clock_t attributeToTenantStart = { 0 };

const char *SharedMemoryNameForMultiTenantMonitorHandleManagement =
	"Shared memory handle for multi tenant monitor";

static shmem_startup_hook_type prev_shmem_startup_hook = NULL;

static void MultiTenantMonitorSMInit(void);
static dsm_handle FindColocationGroupStats(MultiTenantMonitor *multiTenantMonitor);
static dsm_handle FindTenantStats(ColocationGroupStats *stats);
static dsm_handle AddColocationGroupStats(MultiTenantMonitor *monitor);
static dsm_handle AddTenantStats(ColocationGroupStats *stats);
static TenantStats * GetTenantStatsFromDSMHandle(dsm_handle dsmHandle);
static ColocationGroupStats * GetColocationGroupStatsFromDSMHandle(dsm_handle dsmHandle);
static dsm_handle CreateSharedMemoryForTenantStats();

int MultiTenantMonitoringLogLevel = CITUS_LOG_LEVEL_OFF;


PG_FUNCTION_INFO_V1(tenant_monitor);

Datum
tenant_monitor(PG_FUNCTION_ARGS)
{
	//CheckCitusVersion(ERROR);

	TupleDesc tupleDescriptor = NULL;
	Tuplestorestate *tupleStore = SetupTuplestore(fcinfo, &tupleDescriptor);

	Datum values[TENANT_MONITOR_COLUMNS];
	bool isNulls[TENANT_MONITOR_COLUMNS];

	MultiTenantMonitor *monitor = GetMultiTenantMonitor();

	if (monitor == NULL)
	{
		PG_RETURN_VOID();
	}
	

	for (int i=0; i<monitor->colocationGroupCount; i++)
	{
		ColocationGroupStats * colocationGroupStats = GetColocationGroupStatsFromDSMHandle(monitor->colocationGroups[i]);

		for (int j=0; j<colocationGroupStats->tenantCount; j++)
		{
			memset(values, 0, sizeof(values));
			memset(isNulls, false, sizeof(isNulls));

			TenantStats *tenantStats = GetTenantStatsFromDSMHandle(colocationGroupStats->tenants[j]);
			values[0] = Int32GetDatum(colocationGroupStats->colocationGroupId);
			values[1] = PointerGetDatum(cstring_to_text(tenantStats->tenantAttribute));
			values[2] = Int32GetDatum(tenantStats->selectCount);
			values[3] = Float8GetDatum(tenantStats->totalSelectTime);
			values[4] = Int32GetDatum(tenantStats->insertCount);
			values[5] = Float8GetDatum(tenantStats->totalInsertTime);
			

			tuplestore_putvalues(tupleStore, tupleDescriptor, values, isNulls);
		}
	}

	PG_RETURN_VOID();
}


void
AttributeQueryIfAnnotated(const char *query_string, CmdType commandType)
{
	attributeToTenant = NULL;

	attributeCommandType = commandType;

	if (query_string == NULL)
	{
		return;
	}

	if (strncmp(ATTRIBUTE_PREFIX, query_string, strlen(ATTRIBUTE_PREFIX)) == 0)
	{
		/* TODO create a function to safely parse the tenant identifier from the query comment */
		/* query is attributed to a tenant */
		char *tenantId = (char*)query_string + strlen(ATTRIBUTE_PREFIX);
		char *tenantEnd = tenantId;
		while (true && tenantEnd[0] != '\0')
		{
			if (tenantEnd[0] == ' ' && tenantEnd[1] == '*' && tenantEnd[2] == '/')
			{
				break;
			}

			tenantEnd++;
		}
		tenantEnd--;

		colocationGroupId = 0;
		while(*tenantEnd != ',')
		{
			colocationGroupId *= 10;
			colocationGroupId += *tenantEnd - '0';
			tenantEnd--;
		}

		/* hack to get a clean copy of the tenant id string */
		char tenantEndTmp = *tenantEnd;
		*tenantEnd = '\0';
		tenantId = pstrdup(tenantId);
		*tenantEnd = tenantEndTmp;

		if (MultiTenantMonitoringLogLevel != CITUS_LOG_LEVEL_OFF)
		{
			ereport(NOTICE, (errmsg("attributing query to tenant: %s", quote_literal_cstr(tenantId))));
		}

		attributeToTenant = tenantId;
	}
	else
	{
		Assert(attributeToTenant == NULL);
	}

	//DetachSegment();

	attributeToTenantStart = clock();
}

char *
AnnotateQuery (const char * queryString, char * partitionColumn, int colocationId)
{
	if (partitionColumn == NULL)
	{
		return queryString;
	}
	StringInfo newQuery = makeStringInfo();
	appendStringInfo(newQuery, ATTRIBUTE_STRING_FORMAT, partitionColumn, colocationId);

	appendStringInfoString(newQuery, queryString);

	return newQuery->data;
}


void
CitusAttributeToEnd(QueryDesc *queryDesc)
{
	/*
	 * At the end of the Executor is the last moment we have to attribute the previous
	 * attribution to a tenant, if applicable
	 */
	AttributeMetricsIfApplicable();

	/* now call in to the previously installed hook, or the standard implementation */
	if (prev_ExecutorEnd)
	{
		prev_ExecutorEnd(queryDesc);
	}
	else
	{
		standard_ExecutorEnd(queryDesc);
	}
}


static void
AttributeMetricsIfApplicable()
{
	if (attributeToTenant)
	{
		clock_t end = { 0 };
		double cpu_time_used = 0;

		end = clock();
		cpu_time_used = ((double) (end - attributeToTenantStart)) / CLOCKS_PER_SEC;

		if (MultiTenantMonitoringLogLevel != CITUS_LOG_LEVEL_OFF)
		{
			ereport(NOTICE, (errmsg("attribute cpu counter (%f) to tenant: %s", cpu_time_used,
									attributeToTenant)));
		}

		if (GetMultiTenantMonitorDSMHandle() == DSM_HANDLE_INVALID)
		{
			CreateSharedMemoryForMultiTenantMonitor();
		}

		MultiTenantMonitor *monitor = GetMultiTenantMonitor();
		dsm_handle colocationGroupDSMHandle = FindColocationGroupStats(monitor);
		if (colocationGroupDSMHandle == DSM_HANDLE_INVALID)
		{
			colocationGroupDSMHandle = AddColocationGroupStats(monitor);
		}

		ColocationGroupStats * colocationGroupStats = GetColocationGroupStatsFromDSMHandle(colocationGroupDSMHandle);
		colocationGroupStats->colocationGroupId = colocationGroupId;

		dsm_handle tenantDSMHandle = FindTenantStats(colocationGroupStats);

		if (tenantDSMHandle == DSM_HANDLE_INVALID)
		{
			tenantDSMHandle = AddTenantStats(colocationGroupStats);
		}
		TenantStats * tenantStats = GetTenantStatsFromDSMHandle(tenantDSMHandle);
		strcpy(tenantStats->tenantAttribute, attributeToTenant);

		if (attributeCommandType == CMD_SELECT)
		{
			tenantStats->selectCount++;
			tenantStats->totalSelectTime+=cpu_time_used;
		}
		else if (attributeCommandType == CMD_INSERT)
		{
			tenantStats->insertCount++;
			tenantStats->totalInsertTime+=cpu_time_used;
		}

		if (MultiTenantMonitoringLogLevel != CITUS_LOG_LEVEL_OFF)
		{
			ereport(NOTICE, (errmsg("total select count = %d, total CPU time = %f to tenant: %s", tenantStats->selectCount, tenantStats->totalSelectTime,
									tenantStats->tenantAttribute)));
		}
	}
	attributeToTenant = NULL;
}

void
CreateSharedMemoryForMultiTenantMonitor()
{
	struct dsm_segment *dsmSegment = dsm_create(sizeof(MultiTenantMonitor), DSM_CREATE_NULL_IF_MAXSEGMENTS);
	dsm_pin_segment(dsmSegment);
	dsm_pin_mapping(dsmSegment); // don't know why we do both !!!!!!!!!!!!!!!!!
	dsm_handle dsmHandle = dsm_segment_handle(dsmSegment);
	StoreMultiTenantMonitorSMHandle(dsmHandle);
	MultiTenantMonitor * monitor = GetMultiTenantMonitor();
	monitor->colocationGroupCount = 0;
}


static dsm_handle
CreateSharedMemoryForColocationGroupStats()
{
	struct dsm_segment *dsmSegment = dsm_create(sizeof(MultiTenantMonitor), DSM_CREATE_NULL_IF_MAXSEGMENTS);
	dsm_pin_segment(dsmSegment);
	dsm_pin_mapping(dsmSegment); // don't know why we do both !!!!!!!!!!!!!!!!!
	dsm_handle dsmHandle = dsm_segment_handle(dsmSegment);
	ColocationGroupStats * stats = GetColocationGroupStatsFromDSMHandle(dsmHandle);
	stats->tenantCount = 0;
	return dsmHandle;
}


static dsm_handle
CreateSharedMemoryForTenantStats()
{
	struct dsm_segment *dsmSegment = dsm_create(sizeof(TenantStats), DSM_CREATE_NULL_IF_MAXSEGMENTS);
	dsm_pin_segment(dsmSegment);
	dsm_pin_mapping(dsmSegment); // don't know why we do both !!!!!!!!!!!!!!!!!
	return dsm_segment_handle(dsmSegment);
}


MultiTenantMonitor *
GetMultiTenantMonitor()
{
	dsm_handle dsmHandle = GetMultiTenantMonitorDSMHandle();
	if (dsmHandle == DSM_HANDLE_INVALID)
	{
		return NULL;
	}
	dsm_segment *dsmSegment = dsm_find_mapping(dsmHandle);
	if (dsmSegment == NULL)
	{
		dsmSegment = dsm_attach(dsmHandle);
	}
	MultiTenantMonitor *monitor = (MultiTenantMonitor *) dsm_segment_address(dsmSegment);
	dsm_pin_mapping(dsmSegment);
	return monitor;
}


static ColocationGroupStats *
GetColocationGroupStatsFromDSMHandle(dsm_handle dsmHandle)
{
	dsm_segment *dsmSegment = dsm_find_mapping(dsmHandle);
	if (dsmSegment == NULL)
	{
		dsmSegment = dsm_attach(dsmHandle);
	}
	ColocationGroupStats *stats = (ColocationGroupStats *) dsm_segment_address(dsmSegment);
	dsm_pin_mapping(dsmSegment);

	return stats;
}


static TenantStats *
GetTenantStatsFromDSMHandle(dsm_handle dsmHandle)
{
	dsm_segment *dsmSegment = dsm_find_mapping(dsmHandle);
	if (dsmSegment == NULL)
	{
		dsmSegment = dsm_attach(dsmHandle);
	}
	TenantStats *stats = (TenantStats *) dsm_segment_address(dsmSegment);
	dsm_pin_mapping(dsmSegment);

	return stats;
}

void
DetachSegment()
{
	dsm_handle dsmHandle = GetMultiTenantMonitorDSMHandle();
	dsm_segment *dsmSegment = dsm_find_mapping(dsmHandle);
	if (dsmSegment != NULL)
	{
		dsm_detach(dsmSegment);
	}
}

void
InitializeMultiTenantMonitorSMHandleManagement()
{
	prev_shmem_startup_hook = shmem_startup_hook;
	shmem_startup_hook = MultiTenantMonitorSMInit;
}


static void
MultiTenantMonitorSMInit()
{
	bool alreadyInitialized = false;
	MultiTenantMonitorSMData *smData = ShmemInitStruct(SharedMemoryNameForMultiTenantMonitorHandleManagement,
													  sizeof(MultiTenantMonitorSMData),
													  &alreadyInitialized);
	if (!alreadyInitialized)
	{
		smData->dsmHandle = DSM_HANDLE_INVALID;
	}

	if (prev_shmem_startup_hook != NULL)
	{
		prev_shmem_startup_hook();
	}
}

void
StoreMultiTenantMonitorSMHandle(dsm_handle dsmHandle)
{
	bool found = false;
	MultiTenantMonitorSMData *smData = ShmemInitStruct(SharedMemoryNameForMultiTenantMonitorHandleManagement,
													  sizeof(MultiTenantMonitorSMData),
													  &found);


	smData->dsmHandle = dsmHandle;
}

dsm_handle
GetMultiTenantMonitorDSMHandle()
{
	bool found = false;
	MultiTenantMonitorSMData *smData = ShmemInitStruct(SharedMemoryNameForMultiTenantMonitorHandleManagement,
													  sizeof(MultiTenantMonitorSMData),
													  &found);

	if (!found)
	{
		elog(WARNING, "dsm handle not found");
		return DSM_HANDLE_INVALID;
	}

	dsm_handle dsmHandle = smData->dsmHandle;

	return dsmHandle;
}


static dsm_handle
FindColocationGroupStats(MultiTenantMonitor *multiTenantMonitor)
{
	for(int i=0; i<multiTenantMonitor->colocationGroupCount; i++)
	{
		ColocationGroupStats * colocationGroupStats = GetColocationGroupStatsFromDSMHandle(multiTenantMonitor->colocationGroups[i]);
		if (colocationGroupStats->colocationGroupId == colocationGroupId) /// strncmp??!!!!!!!!
		{
			return multiTenantMonitor->colocationGroups[i];
		}
	}

	return DSM_HANDLE_INVALID;
}


static dsm_handle
FindTenantStats(ColocationGroupStats *colocationGroupStats)
{
	for(int i=0; i<colocationGroupStats->tenantCount; i++)
	{
		TenantStats * tenantStats = GetTenantStatsFromDSMHandle(colocationGroupStats->tenants[i]);
		if (strcmp(tenantStats->tenantAttribute, attributeToTenant) == 0) /// strncmp??!!!!!!!!
		{
			return colocationGroupStats->tenants[i];
		}
	}

	return DSM_HANDLE_INVALID;
}


static dsm_handle
AddColocationGroupStats(MultiTenantMonitor *monitor)
{
	dsm_handle dsmHandle = CreateSharedMemoryForColocationGroupStats();
	monitor->colocationGroups[monitor->colocationGroupCount] = dsmHandle;
	monitor->colocationGroupCount++;
	return dsmHandle;
}


static dsm_handle
AddTenantStats(ColocationGroupStats *stats)
{
	dsm_handle dsmHandle = CreateSharedMemoryForTenantStats();
	stats->tenants[stats->tenantCount] = dsmHandle;
	stats->tenantCount++;
	return dsmHandle;
}
