USE [Seller]
GO

/****** Object:  StoredProcedure [dbo].[GetSellerReport]    Script Date: 8/13/2017 5:08:31 AM ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO



CREATE PROCEDURE [dbo].[GetSellerReport]
	@date DATETIME
AS
BEGIN
	SET NOCOUNT ON;

	IF OBJECT_ID('tempdb..#nonulldates') IS NOT NULL
	  DROP TABLE #nonulldates
	IF OBJECT_ID('tempdb..#nulldates') IS NOT NULL
	  DROP TABLE #nulldates
	IF OBJECT_ID('tempdb..#nonulldatesrank') IS NOT NULL
	  DROP TABLE #nonulldatesrank
	IF OBJECT_ID('tempdb..#sellerdatawithlastsaledate') IS NOT NULL
	  DROP TABLE #sellerdatawithlastsaledate
	IF OBJECT_ID('tempdb..#sellerbasedata') IS NOT NULL
	  DROP TABLE #sellerbasedata
	IF OBJECT_ID('tempdb..#sellerdatawithTotalUnitsSold30Days') IS NOT NULL
	  DROP TABLE #sellerdatawithTotalUnitsSold30Days
	IF OBJECT_ID('tempdb..#sellerdatawithTotalNumberOfUnitsSoldBetweenLastStockedAndLastSaleDate') IS NOT NULL
	  DROP TABLE #sellerdatawithTotalNumberOfUnitsSoldBetweenLastStockedAndLastSaleDate

	SELECT ItemNo,[date]
	INTO #nonulldates
	FROM PurchaseHistory
	where [date] is not null AND [date] <> ''

	SELECT ItemNo,[date]
	INTO #nonulldatesrank
	FROM
	(SELECT ItemNo, [Date],
	  row_number() over ( partition by ItemNo order by convert(datetime,[date],111) desc) r 
	FROM #nonulldates
	)
	A
	WHERE r = 1

	SELECT DISTINCT ItemNo,[date]
	INTO #nulldates
	FROM PurchaseHistory
	where [date] is null OR [date] = ''

	SELECT DISTINCT ItemNo,[Date]
	INTO #sellerdatawithlastsaledate
	FROM
	(
	SELECT *
	FROM #nonulldatesrank
	UNION ALL
	SELECT * 
	FROM #nulldates
	) A
 
	SELECT *
	INTO #sellerbasedata
	FROM
	(
		SELECT A.sellername,A.itemno,A.title, A.Quantity,B.Date AS DateLastSale, A.[Date],
			CASE 
				WHEN OutOfStockDate is null AND InStockDate is not null
				THEN InStockDate
				WHEN OutOfStockDate is not null AND InStockDate is not null
				THEN 
					CASE WHEN OutOfStockDate > InStockDate AND OutOfStockDate < DATEADD(DAY,-4,GETDATE())
							THEN dbo.GetDateLastSale(A.ItemNo)
						WHEN OutOfStockDate < InStockDate
							THEN InStockDate
					END
				ELSE null
			END AS DateLastStocked
		FROM PurchaseHistory A
			LEFT JOIN #sellerdatawithlastsaledate  B
			ON B.ItemNo = A.ItemNo
			LEFT JOIN StatusUpdate C 
			ON C.ItemNo = A.ItemNo
		WHERE convert(varchar,convert(datetime ,A.[date]),111) <= convert(varchar,convert(date, @date) ,111) 

		UNION ALL 

		SELECT A.sellername,A.itemno,A.title, A.Quantity, B.Date AS DateLastSale,A.[Date],
			CASE 
				WHEN OutOfStockDate is null AND InStockDate is not null
				THEN InStockDate
				WHEN OutOfStockDate is not null AND InStockDate is not null
				THEN 
					CASE WHEN OutOfStockDate > InStockDate AND OutOfStockDate < DATEADD(DAY,-4,GETDATE())
							THEN dbo.GetDateLastSale(A.ItemNo)
						WHEN OutOfStockDate < InStockDate
							THEN InStockDate
					END
				ELSE null
			END AS DateLastStocked
		FROM PurchaseHistory A
			LEFT JOIN #sellerdatawithlastsaledate  B
			ON B.ItemNo = A.ItemNo
			LEFT JOIN StatusUpdate C 
			ON C.ItemNo = A.ItemNo
		WHERE  A.[date] is null OR A.[date] = ''
	)A
	GROUP BY sellername,A.itemno,title, DateLastSale, DateLastStocked, Quantity,Date
	
	
	SELECT ItemNo, ISNULL(SUM(CAST(Quantity AS INT)),0) AS TotalUnitsSold30Days
	INTO #sellerdatawithTotalUnitsSold30Days
	FROM purchasehistory
	WHERE convert(datetime,[date],111) between convert(date,DATEADD(day,-30,@date) ,111)  and convert(varchar,convert(date, @date) ,111)
	GROUP BY ItemNo

	SELECT ItemNo, ISNULL(SUM(CAST(Quantity AS INT)),0) AS TotalNumberOfUnitsSoldBetweenLastStockedAndLastSaleDate
	INTO #sellerdatawithTotalNumberOfUnitsSoldBetweenLastStockedAndLastSaleDate
	FROM #sellerbasedata
	WHERE ([date] >= DateLastStocked AND [date] <= DateLastSale)
	  OR (DateLastStocked IS NULL AND DateLastSale IS NULL)
	  OR (DateLastStocked IS NULL AND [date] <= DateLastSale)
	  OR (DateLastSale IS NULL AND [date] >= DateLastStocked)
	GROUP BY ItemNo

	SELECT SellerName, A.ItemNo, Title, ISNULL(SUM(CAST(Quantity AS INT)),0) AS TotalQuantitySold, DateLastSale,DateLastStocked, TotalUnitsSold30Days, 
	  DATEDIFF(day,DateLastSale,DateLastStocked) AS TotalNumberOfDaysBetweenLastStockedAndLastSaleDate, TotalNumberOfUnitsSoldBetweenLastStockedAndLastSaleDate
	FROM #sellerbasedata A
	LEFT JOIN #sellerdatawithTotalUnitsSold30Days B ON B.ItemNo = A.ItemNo
	LEFT JOIN #sellerdatawithTotalNumberOfUnitsSoldBetweenLastStockedAndLastSaleDate C ON C.ItemNo = A.ItemNo
	GROUP BY sellername,A.itemno,title, DateLastSale, DateLastStocked,B.TotalUnitsSold30Days, C.TotalNumberOfUnitsSoldBetweenLastStockedAndLastSaleDate

END

GO


