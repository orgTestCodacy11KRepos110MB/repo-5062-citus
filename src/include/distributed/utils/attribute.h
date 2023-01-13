//
// Created by Nils Dijk on 02/12/2022.
//

#ifndef CITUS_ATTRIBUTE_H
#define CITUS_ATTRIBUTE_H

#include "executor/execdesc.h"
#include "executor/executor.h"

typedef struct MultiTenantMonitor
{
	int colocationGroupCount;
	dsm_handle colocationGroups[100];
} MultiTenantMonitor;

typedef struct ColocationGroupStats
{
	int colocationGroupId;
	
	int tenantCount;
	dsm_handle tenants[100];
} ColocationGroupStats;

typedef struct TenantStats
{
	char tenantAttribute[100];

	int selectCount;
	double totalSelectTime;

	int insertCount;
	double totalInsertTime;
} TenantStats;

typedef struct MultiTenantMonitorSMData
{
	dsm_handle dsmHandle;
} MultiTenantMonitorSMData;

extern void CitusAttributeToEnd(QueryDesc *queryDesc);
extern void AttributeQueryIfAnnotated(const char *queryString, CmdType commandType);
extern char * AnnotateQuery(const char *queryString, char * partitionColumn, int colocationId);
extern void CreateSharedMemoryForMultiTenantMonitor(void);
extern MultiTenantMonitor * GetMultiTenantMonitor(void);
extern void DetachSegment(void);
extern void InitializeMultiTenantMonitorSMHandleManagement(void);
extern void StoreMultiTenantMonitorSMHandle(dsm_handle dsmHandle);
extern dsm_handle GetMultiTenantMonitorDSMHandle(void);

extern ExecutorEnd_hook_type prev_ExecutorEnd;

extern int MultiTenantMonitoringLogLevel;

#endif //CITUS_ATTRIBUTE_H
