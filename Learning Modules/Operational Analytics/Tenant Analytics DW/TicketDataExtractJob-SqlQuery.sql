-- Connect to and run against the jobaccount database in catalog-<WtpUser> server
-- Replace <WtpUser> below with your user name
DECLARE @WtpUser nvarchar(50);
DECLARE @server1 nvarchar(50);
DECLARE @server2 nvarchar(50);
SET @WtpUser = '<WtpUser>';

-- Add a target group containing server(s)
EXEC [jobs].sp_add_target_group @target_group_name = 'TenantGroup'

-- Add a server target member, includes all databases in tenant server
SET @server1 = 'customers1-' + @WtpUser + '.database.windows.net'

EXEC [jobs].sp_add_target_group_member
@target_group_name = 'TenantGroup',
@membership_type = 'Include',
@target_type = 'SqlServer',
@refresh_credential_name='myrefreshcred',
@server_name=@server1

-- Create job to retrieve analytics that are distributed across all the tenants
EXEC jobs.sp_add_job
@job_name='Ticket Purchases from all Tenants',
@description='Retrieve tenant telemetry data from all tenants',
@enabled=1,
@schedule_interval_type='Once'

-- Create job step to retrieve analytics that are distributed across all the tenants
SET @server2 = 'catalog-' + @WtpUser + '.database.windows.net'

EXEC jobs.sp_add_jobstep
@job_name='Ticket Purchases from all Tenants',
@command=N'
WITH Venues_CTE (VenueId, VenueName, VenueType, VenuePostalCode, VenueCapacity, X)
AS
   (SELECT TOP 1 Convert(int, HASHBYTES(''md5'',VenueName)) AS VenueId, VenueName, VenueType, PostalCode AS VenuePostalCode,
		(SELECT SUM ([SeatRows]*[SeatsPerRow]) FROM [dbo].[Sections]) AS VenueCapacity,
    1 AS X FROM Venues)
SELECT v.VenueId, v.VenueName, v.VenueType,v.VenuePostalCode, v.VenueCapacity, tp.TicketPurchaseId, tp.PurchaseDate, tp.PurchaseTotal, c.CustomerId, c.PostalCode as CustomerPostalCode, c.CountryCode, e.EventId, e.EventName, e.Subtitle as EventSubtitle, e.Date as EventDate, $(job_execution_id) as job_execution_id FROM 
Venues_CTE as v
INNER JOIN TicketPurchases AS tp ON v.X = 1
INNER JOIN Tickets AS t ON t.TicketPurchaseId = tp.TicketPurchaseId
INNER JOIN Events AS e ON t.EventId = e.EventId
INNER JOIN Customers AS c ON tp.CustomerId = c.CustomerId',
@credential_name='mydemocred',
@target_group_name='TenantGroup',
@output_type='SqlDatabase',
@output_credential_name='mydemocred',
@output_server_name=@server2,
@output_database_name='tenantanalytics',
@output_table_name='AllTicketsPurchasesfromAllTenants'

--
-- Views
-- Job and Job Execution Information and Status
--
SELECT * FROM [jobs].[jobs] 
WHERE job_name = 'Ticket Purchases from all Tenants'

SELECT * FROM [jobs].[jobsteps] 
WHERE job_name = 'Ticket Purchases from all Tenants'

WAITFOR DELAY '00:00:10'
--View parent execution status
SELECT * FROM [jobs].[job_executions] 
WHERE job_name = 'Ticket Purchases from all Tenants' and step_id IS NULL

--View all execution status
SELECT * FROM [jobs].[job_executions] 
WHERE job_name = 'Ticket Purchases from all Tenants'

--Stop a running job, requires active job_execution_id from [jobs].[job_executions] view
--EXEC [jobs].[sp_stop_job] 'F15CA86F-5B00-4B47-B3B8-94009A93DC17'

-- Cleanup
--EXEC [jobs].[sp_delete_job] 'Ticket Purchases from all Tenants'
--EXEC [jobs].[sp_delete_target_group] 'TenantGroup'