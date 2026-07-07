USE HD_A01;
SET NOCOUNT ON; SET DATEFORMAT DMY; SET ROWCOUNT 0;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @RutaFinal nvarchar(500)=N'D:\RESPALDO_PROFIT\CIERRE',
        @cmd nvarchar(2000), @srv nvarchar(200)=@@servername,
        @desde datetime=cast(cast(getdate() as date) as datetime),
        @hasta datetime=getdate();

DECLARE @tasa decimal(18,6)=(SELECT MAX(tasa) FROM docum_cc WITH(NOLOCK)
                             WHERE tipo_doc='FACT' AND tasa>1 AND fec_emis BETWEEN @desde AND @hasta);

DECLARE @elec decimal(18,2),@hog decimal(18,2),@bod decimal(18,2),@vtot decimal(18,2);
;WITH mov AS (
  SELECT CASE WHEN a.co_lin='BODG' THEN 'B' WHEN a.co_lin IN ('LEN','NAC') THEN 'H' ELSE 'E' END dep,
         r.reng_neto/nullif(d.tasa,0) monto
  FROM docum_cc d WITH(NOLOCK)
  JOIN reng_fac r WITH(NOLOCK) ON r.fact_num=d.nro_doc
  JOIN art a WITH(NOLOCK) ON a.co_art=r.co_art
  WHERE d.tipo_doc='FACT' AND d.anulado=0 AND a.anulado=0 AND d.fec_emis BETWEEN @desde AND @hasta
  UNION ALL
  SELECT CASE WHEN a.co_lin='BODG' THEN 'B' WHEN a.co_lin IN ('LEN','NAC') THEN 'H' ELSE 'E' END,
         -1*(rd.reng_neto/nullif(dc.tasa,0))
  FROM dev_cli dc WITH(NOLOCK)
  JOIN reng_dvc rd WITH(NOLOCK) ON rd.fact_num=dc.fact_num
  JOIN art a WITH(NOLOCK) ON a.co_art=rd.co_art
  WHERE a.anulado=0 AND dc.fec_emis BETWEEN @desde AND @hasta
)
SELECT @elec=SUM(CASE WHEN dep='E' THEN monto END),
       @hog =SUM(CASE WHEN dep='H' THEN monto END),
       @bod =SUM(CASE WHEN dep='B' THEN monto END),
       @vtot=SUM(monto) FROM mov;

DECLARE @cobUSD decimal(18,2),@cobBS decimal(18,2),@porCobrar decimal(18,2);
DECLARE @iniUSD decimal(18,2),@iniBS decimal(18,2);

SELECT @iniUSD=ISNULL(SUM(CASE WHEN LTRIM(RTRIM(m.moneda))='US$' THEN m.monto_h ELSE 0 END),0),
       @iniBS =ISNULL(SUM(CASE WHEN LTRIM(RTRIM(m.moneda))='BS'  THEN m.monto_h ELSE 0 END),0)
FROM mov_caj m WITH(NOLOCK)
WHERE m.anulado=0 AND LTRIM(RTRIM(m.origen))='COB'
  AND m.fecha BETWEEN @desde AND @hasta
  AND EXISTS(SELECT 1 FROM reng_cob rc WITH(NOLOCK)
             JOIN factura f WITH(NOLOCK) ON f.fact_num=rc.doc_num
             WHERE rc.cob_num=m.cob_pag AND LTRIM(RTRIM(rc.tp_doc_cob))='FACT'
               AND LTRIM(RTRIM(f.forma_pag))='CASH' AND f.anulada=0);

SET @iniBS=@iniBS/NULLIF(@tasa,0);

SELECT @cobUSD=SUM(CASE WHEN LTRIM(RTRIM(moneda))='US$' THEN monto_h ELSE 0 END),
       @cobBS =SUM(CASE WHEN LTRIM(RTRIM(moneda))='BS'  THEN monto_h ELSE 0 END)/NULLIF(@tasa,0)
FROM mov_caj WITH(NOLOCK)
WHERE anulado=0 AND LTRIM(RTRIM(origen))='COB' AND fecha BETWEEN @desde AND @hasta;

SET @cobUSD=ISNULL(@cobUSD,0)-@iniUSD;
SET @cobBS=ISNULL(@cobBS,0)-@iniBS;

SELECT @porCobrar=SUM(saldo/NULLIF(tasa,0))
FROM docum_cc WITH(NOLOCK)
WHERE tipo_doc='FACT' AND anulado=0 AND saldo<>0 AND fec_emis BETWEEN @desde AND @hasta;

SET @elec=ISNULL(@elec,0); SET @hog=ISNULL(@hog,0); SET @bod=ISNULL(@bod,0); SET @vtot=ISNULL(@vtot,0);
SET @cobUSD=ISNULL(@cobUSD,0); SET @cobBS=ISNULL(@cobBS,0); SET @porCobrar=ISNULL(@porCobrar,0);
DECLARE @cashea decimal(18,2)=@vtot-@cobUSD-@cobBS-@porCobrar;
DECLARE @ctot decimal(18,2)=@cobUSD+@cobBS+@cashea+@porCobrar;

EXEC xp_cmdshell N'cmd /c if not exist "D:\RESPALDO_PROFIT\CIERRE" md "D:\RESPALDO_PROFIT\CIERRE"', NO_OUTPUT;
EXEC xp_cmdshell N'FORFILES /p D:\RESPALDO_PROFIT\CIERRE /m *.csv  /c "CMD /C del /Q /F @FILE"', NO_OUTPUT;
EXEC xp_cmdshell N'FORFILES /p D:\RESPALDO_PROFIT\CIERRE /m *.html /c "CMD /C del /Q /F @FILE"', NO_OUTPUT;

IF OBJECT_ID('tempdb..##c') IS NOT NULL DROP TABLE ##c;
CREATE TABLE ##c(_o int, seccion varchar(20), concepto varchar(40), monto_OM varchar(20));
INSERT INTO ##c VALUES
 (0,'SECCION','CONCEPTO','MONTO_OM'),
 (1,'VENTAS','Electrodomesticos',convert(varchar,@elec)),
 (2,'VENTAS','Hogar',convert(varchar,@hog)),
 (3,'VENTAS','Bodegon',convert(varchar,@bod)),
 (4,'VENTAS','TOTAL VENTAS',convert(varchar,@vtot)),
 (5,'COBROS','Cobro en $',convert(varchar,@cobUSD)),
 (6,'COBROS','Cobro en Bs',convert(varchar,@cobBS)),
 (7,'COBROS','Por Cobrar Cashea',convert(varchar,@cashea)),
 (8,'COBROS','Cuentas por Cobrar',convert(varchar,@porCobrar)),
 (9,'COBROS','TOTAL COBROS',convert(varchar,@ctot));
SET @cmd=N'bcp "select seccion,concepto,monto_OM from ##c order by _o" queryout "'+@RutaFinal+N'\INFORME_CIERRE_KD.csv" -U profit -P profit -S '+@srv+N' -c -t; -T -k';
EXEC xp_cmdshell @cmd, NO_OUTPUT;

DECLARE @f varchar(10)=convert(varchar,@hasta,103);
DECLARE @h nvarchar(max)=
 N'<div style="font-family:Arial,sans-serif;color:#222;">'
+N'<h2 style="color:#1F3A5F;margin:0 0 2px;">HOUSE DEPOT PF, S.A.</h2>'
+N'<div style="font-weight:bold;">Cierre de Caja Diario (OM)</div>'
+N'<div style="font-size:12px;color:#666;margin:2px 0 12px;">Fecha: '+@f+N' &middot; Montos en OM (divisa) &middot; Tasa: '+convert(varchar,cast(@tasa as money),1)+N'</div>'
+N'<table style="border-collapse:collapse;font-size:12px;margin-bottom:14px;">'
+N'<tr style="background:#1F3A5F;color:#fff;"><td colspan="2" style="padding:6px 12px;"><b>VENTAS POR DEPARTAMENTO</b></td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:5px 12px;">Electrodom&eacute;sticos</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;">'+convert(varchar,cast(@elec as money),1)+N'</td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:5px 12px;">Hogar</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;">'+convert(varchar,cast(@hog as money),1)+N'</td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:5px 12px;">Bodeg&oacute;n</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;">'+convert(varchar,cast(@bod as money),1)+N'</td></tr>'
+N'<tr style="background:#eef;font-weight:bold;"><td style="border:1px solid #bfbfbf;padding:5px 12px;">TOTAL VENTAS</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;color:#1F3A5F;">'+convert(varchar,cast(@vtot as money),1)+N'</td></tr>'
+N'</table>'
+N'<table style="border-collapse:collapse;font-size:12px;">'
+N'<tr style="background:#1F3A5F;color:#fff;"><td colspan="2" style="padding:6px 12px;"><b>FORMAS DE COBRO</b></td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:5px 12px;">Cobro en $</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;">'+convert(varchar,cast(@cobUSD as money),1)+N'</td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:5px 12px;">Cobro en Bs</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;">'+convert(varchar,cast(@cobBS as money),1)+N'</td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:5px 12px;">Por Cobrar Cashea</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;">'+convert(varchar,cast(@cashea as money),1)+N'</td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:5px 12px;">Cuentas por Cobrar</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;">'+convert(varchar,cast(@porCobrar as money),1)+N'</td></tr>'
+N'<tr style="background:#eef;font-weight:bold;"><td style="border:1px solid #bfbfbf;padding:5px 12px;">TOTAL COBROS</td><td align="right" style="border:1px solid #bfbfbf;padding:5px 12px;color:#1F3A5F;">'+convert(varchar,cast(@ctot as money),1)+N'</td></tr>'
+N'</table>'
+N'<p style="font-size:11px;color:#888;margin-top:12px;">Generado autom&aacute;ticamente desde Profit Plus (HD_A01) &middot; Cashea = financiado (Ventas &minus; Cobros &minus; Ctas x Cobrar)</p></div>';

IF OBJECT_ID('tempdb..##h') IS NOT NULL DROP TABLE ##h;
CREATE TABLE ##h(html nvarchar(max)); INSERT INTO ##h VALUES(@h);
SET @cmd=N'bcp "select html from ##h" queryout "'+@RutaFinal+N'\INFORME_CIERRE_KD.html" -U profit -P profit -S '+@srv+N' -c -t; -T -k';
EXEC xp_cmdshell @cmd, NO_OUTPUT;

DROP TABLE ##c; DROP TABLE ##h;
