USE HD_A01;
SET NOCOUNT ON; SET DATEFORMAT DMY; SET ROWCOUNT 0;
SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED;

DECLARE @RutaFinal nvarchar(500)=N'D:\RESPALDO_PROFIT\MARGEN',
        @cmd nvarchar(2000), @srv nvarchar(200)=@@servername,
        @desde datetime=cast(cast(getdate() as date) as datetime),
        @hasta datetime=getdate(),
        @rows nvarchar(max)=N'',
        @h nvarchar(max)=N'',
        @tVend decimal(18,2),@tNeto decimal(18,2),@tDevN decimal(18,2),
        @tCosto decimal(18,2),@tCdev decimal(18,2),@tGan decimal(18,2),
        @vNet decimal(18,2),@cNet decimal(18,2),@gNet decimal(18,2),@marg decimal(18,2);

IF OBJECT_ID('tempdb..##vx1') IS NOT NULL DROP TABLE ##vx1;
CREATE TABLE ##vx1(
     Mes char(7),Linea char(60),Sub_Linea char(60),Articulo char(120),Unid char(10)
    ,Stock char(14),Vendido char(14),Devuelto char(14),Neto_OM char(16),Devol_OM char(16)
    ,Costo_OM char(16),CostoDev_OM char(16),Ganancia_OM char(16),Margen_Pct char(10));

;WITH ventas AS(
   select a.co_lin,a.co_subl,a.co_art,a.art_des,a.uni_venta
         ,sum(r.total_art) total_art, sum(r.reng_neto/nullif(d.tasa,0)) monto_net
         ,sum(r.total_art*r.ult_cos_om) costo
   from docum_cc d with(nolock)
   join reng_fac r with(nolock) on r.fact_num=d.nro_doc
   join art a with(nolock) on a.co_art=r.co_art
   where d.tipo_doc='FACT' and d.anulado=0 and a.anulado=0 and d.fec_emis between @desde and @hasta
   group by a.co_lin,a.co_subl,a.co_art,a.art_des,a.uni_venta),
devol AS(
   select a.co_art, sum(rd.total_art) total_dev, sum(rd.reng_neto/nullif(dc.tasa,0)) dev
         ,sum(rd.total_art*rd.ult_cos_om) devcosto
   from dev_cli dc with(nolock)
   join reng_dvc rd with(nolock) on rd.fact_num=dc.fact_num
   join art a with(nolock) on a.co_art=rd.co_art
   where a.anulado=0 and dc.fec_emis between @desde and @hasta
   group by a.co_art)
INSERT INTO ##vx1
 select convert(char(7),' Mes'),convert(char(60),'Linea'),convert(char(60),'Sub_Linea'),convert(char(120),'Articulo'),convert(char(10),'Unid'),convert(char(14),'Stock'),convert(char(14),'Vendido'),convert(char(14),'Devuelto'),convert(char(16),'Neto_OM'),convert(char(16),'Devol_OM'),convert(char(16),'Costo_OM'),convert(char(16),'CostoDev_OM'),convert(char(16),'Ganancia_OM'),convert(char(10),'Margen_%')
 union all
 select convert(char(7),right('0'+convert(varchar,month(@hasta)),2)+'/'+convert(varchar,year(@hasta)))
   ,convert(char(60),ltrim(rtrim(v.co_lin))+' '+ltrim(rtrim(l.lin_des)))
   ,convert(char(60),ltrim(rtrim(v.co_subl))+' '+ltrim(rtrim(s.subl_des)))
   ,convert(char(120),ltrim(rtrim(upper(v.art_des)))),convert(char(10),ltrim(rtrim(v.uni_venta)))
   ,convert(char(14),convert(varchar,convert(decimal(14,2),isnull(sa.stock_act,0))))
   ,convert(char(14),convert(varchar,convert(decimal(14,2),v.total_art)))
   ,convert(char(14),convert(varchar,convert(decimal(14,2),isnull(dv.total_dev,0))))
   ,convert(char(16),convert(varchar,convert(decimal(16,2),v.monto_net)))
   ,convert(char(16),convert(varchar,convert(decimal(16,2),isnull(dv.dev,0))))
   ,convert(char(16),convert(varchar,convert(decimal(16,2),v.costo)))
   ,convert(char(16),convert(varchar,convert(decimal(16,2),isnull(dv.devcosto,0))))
   ,convert(char(16),convert(varchar,convert(decimal(16,2),(v.monto_net-v.costo)-(isnull(dv.dev,0)-isnull(dv.devcosto,0)))))
   ,convert(char(10),convert(varchar,convert(decimal(10,2),((v.monto_net-v.costo)-(isnull(dv.dev,0)-isnull(dv.devcosto,0)))/nullif(v.monto_net-isnull(dv.dev,0),0)*100)))
 from ventas v
 join lin_art l with(nolock) on l.co_lin=v.co_lin
 join sub_lin s with(nolock) on s.co_subl=v.co_subl and s.co_lin=v.co_lin
 left join devol dv on dv.co_art=v.co_art
 left join st_almac sa with(nolock) on sa.co_art=v.co_art and sa.co_alma='03';

EXEC xp_cmdshell N'cmd /c if not exist "D:\RESPALDO_PROFIT\MARGEN" md "D:\RESPALDO_PROFIT\MARGEN"', NO_OUTPUT;

SET @cmd=N'bcp "select * from ##vx1 order by 1,2,3,4" queryout "'+@RutaFinal+N'\INFORME_MARGEN_KD.csv" -U profit -P profit -S '+@srv+N' -c -t; -T -k';
EXEC xp_cmdshell @cmd, NO_OUTPUT;

SELECT @rows = @rows + N'<tr>'
 +N'<td style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Linea)),N'')+N'</td>'
 +N'<td style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Sub_Linea)),N'')+N'</td>'
 +N'<td style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Articulo)),N'')+N'</td>'
 +N'<td align="right" style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Stock)),N'')+N'</td>'
 +N'<td align="right" style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Vendido)),N'')+N'</td>'
 +N'<td align="right" style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Neto_OM)),N'')+N'</td>'
 +N'<td align="right" style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Costo_OM)),N'')+N'</td>'
 +N'<td align="right" style="border:1px solid #bfbfbf;padding:4px;">'+isnull(ltrim(rtrim(Ganancia_OM)),N'')+N'</td>'
 +N'<td align="right" style="border:1px solid #bfbfbf;padding:4px;"><b>'+isnull(ltrim(rtrim(Margen_Pct)),N'')+N'%</b></td></tr>'
FROM ##vx1 WHERE ltrim(rtrim(Mes))<>'Mes';

SELECT @tVend=sum(cast(Vendido as decimal(18,2))),@tNeto=sum(cast(Neto_OM as decimal(18,2))),
       @tDevN=sum(cast(Devol_OM as decimal(18,2))),@tCosto=sum(cast(Costo_OM as decimal(18,2))),
       @tCdev=sum(cast(CostoDev_OM as decimal(18,2))),@tGan=sum(cast(Ganancia_OM as decimal(18,2)))
FROM ##vx1 WHERE ltrim(rtrim(Mes))<>'Mes';
SET @vNet=@tNeto-@tDevN; SET @cNet=@tCosto-@tCdev;
SET @gNet=@vNet-@cNet; SET @marg=case when @vNet=0 then 0 else @gNet/@vNet*100 end;

SET @h=N'<div style="font-family:Arial,sans-serif;color:#222;">'
+N'<h2 style="color:#1F3A5F;margin:0 0 2px;">HOUSE DEPOT PF, S.A.</h2>'
+N'<div style="font-weight:bold;">Informe de Margen por Art&iacute;culo (OM)</div>'
+N'<div style="font-size:12px;color:#666;margin:2px 0 10px;">Per&iacute;odo: '+convert(varchar,@hasta,103)+N' &middot; Montos en OM (divisa) &middot; Margen sobre venta</div>'
+N'<table style="border-collapse:collapse;font-size:11px;">'
+N'<tr style="background:#1F3A5F;color:#fff;">'
+N'<td style="padding:5px;">L&iacute;nea</td><td style="padding:5px;">Sub-L&iacute;nea</td><td style="padding:5px;">Art&iacute;culo</td>'
+N'<td style="padding:5px;">Stock</td><td style="padding:5px;">Vend.</td><td style="padding:5px;">Neto OM</td>'
+N'<td style="padding:5px;">Costo OM</td><td style="padding:5px;">Ganancia OM</td><td style="padding:5px;">Margen %</td></tr>'
+@rows
+N'<tr style="background:#1F3A5F;color:#fff;font-weight:bold;">'
+N'<td colspan="3" style="padding:5px;">TOTALES</td>'
+N'<td style="padding:5px;"></td>'
+N'<td align="right" style="padding:5px;">'+convert(varchar,cast(@tVend as money),1)+N'</td>'
+N'<td align="right" style="padding:5px;">'+convert(varchar,cast(@tNeto as money),1)+N'</td>'
+N'<td align="right" style="padding:5px;">'+convert(varchar,cast(@tCosto as money),1)+N'</td>'
+N'<td align="right" style="padding:5px;">'+convert(varchar,cast(@tGan as money),1)+N'</td>'
+N'<td align="right" style="padding:5px;">'+convert(varchar,@marg)+N'%</td></tr>'
+N'</table>'
+N'<table style="border-collapse:collapse;font-size:12px;margin-top:14px;">'
+N'<tr style="background:#1F3A5F;color:#fff;"><td colspan="2" style="padding:6px 10px;"><b>RESUMEN (OM)</b></td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:6px 10px;">Total Ventas - Devoluciones</td><td align="right" style="border:1px solid #bfbfbf;padding:6px 10px;"><b>'+convert(varchar,cast(@vNet as money),1)+N'</b></td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:6px 10px;">Costo de Venta - Devoluciones</td><td align="right" style="border:1px solid #bfbfbf;padding:6px 10px;"><b>'+convert(varchar,cast(@cNet as money),1)+N'</b></td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:6px 10px;"><b>Ganancia Neta</b></td><td align="right" style="border:1px solid #bfbfbf;padding:6px 10px;color:#1F3A5F;"><b>'+convert(varchar,cast(@gNet as money),1)+N'</b></td></tr>'
+N'<tr><td style="border:1px solid #bfbfbf;padding:6px 10px;"><b>Margen sobre venta</b></td><td align="right" style="border:1px solid #bfbfbf;padding:6px 10px;color:#1F3A5F;"><b>'+convert(varchar,@marg)+N'%</b></td></tr>'
+N'</table>'
+N'<p style="font-size:11px;color:#888;margin-top:12px;">Generado autom&aacute;ticamente desde Profit Plus (HD_A01) &middot; Valores en Otra Moneda</p></div>';

IF OBJECT_ID('tempdb..##h') IS NOT NULL DROP TABLE ##h;
CREATE TABLE ##h(html nvarchar(max));
INSERT INTO ##h VALUES(@h);
SET @cmd=N'bcp "select html from ##h" queryout "'+@RutaFinal+N'\INFORME_MARGEN_KD.html" -U profit -P profit -S '+@srv+N' -c -t; -T -k';
EXEC xp_cmdshell @cmd, NO_OUTPUT;

DROP TABLE ##vx1; DROP TABLE ##h;
