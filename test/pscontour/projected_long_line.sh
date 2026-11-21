#!/usr/bin/env bash
# A contour within a projected triangle is continuous, even across half a world map.
# Compare all strongly magenta pixels with a straight psxy reference.
set -e
cat > triangle.xyz << EOF
170 -30 -30
170 30 30
-180 -30 -30
EOF
cat > reference.xy << EOF
-92.5 -15
0 -15
90 -15
170 -15
EOF
gmt pscontour triangle.xyz -R-180/180/-30/30 -JQ0/10c -fg -C-15, -A- -W2p,magenta -P -Baf -BWSen > contour.ps
gmt psxy reference.xy -R-180/180/-30/30 -JQ0/10c -fg -A -N -W2p,magenta -P -Baf -BWSen > reference.ps
gmt psconvert contour.ps -A -Tg -E144
gmt psconvert reference.ps -A -Tg -E144
contour_size=$("${GRAPHICSMAGICK:-gm}" identify -format '%wx%h' contour.png)
reference_size=$("${GRAPHICSMAGICK:-gm}" identify -format '%wx%h' reference.png)
if [ "$contour_size" != "$reference_size" ]; then
  printf 'Image sizes differ: %s vs %s\n' "$contour_size" "$reference_size" >&2
  false
fi
"${GRAPHICSMAGICK:-gm}" convert reference.png -depth 8 txt:- > reference.rgb
"${GRAPHICSMAGICK:-gm}" convert contour.png -depth 8 txt:- > contour.rgb
"${AWK:-awk}" '
function value(pair,  a,b) {
  a = index("0123456789ABCDEF", substr(pair,1,1)) - 1
  b = index("0123456789ABCDEF", substr(pair,2,1)) - 1
  return 16*a+b
}
function magenta(hex) {
  hex = toupper(hex)
  return value(substr(hex,2,2)) > 175 && value(substr(hex,4,2)) < 85 && value(substr(hex,6,2)) > 175
}
FNR == NR { if (magenta($NF)) { reference[$1]=1; expected++ } next }
{ if (magenta($NF)) { if (reference[$1]) covered++; else outside++ } }
END {
  printf "reference=%d covered=%d outside=%d\n", expected, covered, outside
  if (expected < 1000 || covered != expected || outside != 0) exit 1
}' reference.rgb contour.rgb

# A sparse and a dense projected mesh have the same labelled contour.
for x in -92.5 0 90 170; do
  printf '%s -30 -30\n%s 30 30\n' "$x" "$x"
done > dense.xyz
gmt pscontour triangle.xyz -R-180/180/-30/30 -JQ0/10c -fg -C-15, -A-15,+f12p,Helvetica,black+tsparse-labels.txt -Gn1 -W2p,magenta -P -Baf -BWSen > sparse-labels.ps
gmt pscontour dense.xyz -R-180/180/-30/30 -JQ0/10c -fg -C-15, -A-15,+f12p,Helvetica,black+tdense-labels.txt -Gn1 -W2p,magenta -P -Baf -BWSen > dense-labels.ps
"${AWK:-awk}" 'NF >= 4 { n++; if ($1 < 38.749 || $1 > 38.751 || $2 != -15) bad=1 } END { exit (bad || n != 1) }' sparse-labels.txt
cmp sparse-labels.txt dense-labels.txt
gmt psconvert sparse-labels.ps -A -Tg -E144
gmt psconvert dense-labels.ps -A -Tg -E144
"${GRAPHICSMAGICK:-gm}" convert sparse-labels.png -depth 8 txt:- > sparse-labels.rgb
"${GRAPHICSMAGICK:-gm}" convert dense-labels.png -depth 8 txt:- > dense-labels.rgb
cmp sparse-labels.rgb dense-labels.rgb
printf 'Label position and labelled image match the dense mesh\n'

# These inputs describe the same long projected contour.  Crossing tracks are
# already in plot units when the contour-label machinery searches for xovers.
# Check both label coordinates and the actual PostScript path endpoints.
printf '0 -30 0\n0 30 0\n' > crossing.xy
for spec in 'triangle.xyz 700 -Gl0/-30/0/30' 'dense.xyz 700 -Gl0/-30/0/30' 'triangle.xyz 600 -Gl0/-30/0/30' 'triangle.xyz 700 -Gn1' 'triangle.xyz 700 -Gxcrossing.xy' 'triangle.xyz 700 -GXcrossing.xy' 'triangle.xyz 700 -GL0/-30/0/30'; do
  read -r input width opt <<< "$spec"
  tag="${input%.xyz}-$width-${opt:2:1}"
  gmt pscontour "$input" -R-180/180/-30/30 "-JQ0/${width}c" -fg "-A-15,+t$tag.txt" "$opt" -W2p,magenta -P --PS_MEDIA=710cx130c > "$tag.ps"
  if [ "$opt" = -Gn1 ]; then want=38.75; else want=0; fi
  "${AWK:-awk}" -v want="$want" -v tag="$tag" 'NF >= 4 {n++; if (($1-want)^2 > 1e-8 || ($2+15)^2 > 1e-8) bad=1} END {printf "%s labels=%d\n",tag,n; exit !(n==1&&!bad)}' "$tag.txt"
  "${AWK:-awk}" -v width="$width" -v tag="$tag" '
    /%%BeginObject PSL_Layer_1/ {body=1}
    body && NF==3 && $3=="M" && $1 ~ /^-?[0-9]+$/ && $2==(width==700?13780:11811) {x=$1;lo=hi=x;found=1;next}
    body && found && NF==3 && $3=="D" && $1 ~ /^-?[0-9]+$/ && $2==0 {x+=$1;if(x<lo)lo=x;if(x>hi)hi=x}
    END {a=(width==700?80381:68898);b=(width==700?321522:275591);printf "%s path=[%d,%d] expected=[%d,%d]\n",tag,lo,hi,a,b;exit !(found&&lo==a&&hi==b)}' "$tag.ps"
done

# Reference distances follow pscontour's configured WGS-84 Vincenty model.
# Sample the actual inverse-projected line independently, in km and degrees.
"${AWK:-awk}" 'BEGIN {for(i=0;i<=1050;i++) printf "%.16g -15\n",170-i*.25}' > distance-samples.xy
gmt mapproject distance-samples.xy -G+uk+a -je -fg --FORMAT_FLOAT_OUT=%.16g > distance-km.tsv
gmt mapproject distance-samples.xy -G+ud+a -je -fg --FORMAT_FLOAT_OUT=%.16g > distance-deg.tsv
"${AWK:-awk}" 'NR>1 {while($3>=5000*(n+1)){n++;f=(5000*n-pd)/($3-pd);printf "%.16g -15\n",px+f*($1-px)}} {px=$1;pd=$3} END {if(n!=5)exit 1}' distance-km.tsv > distance-expected.xy
for input in triangle.xyz dense.xyz; do
  tag="distance-${input%.xyz}"
  gmt pscontour "$input" -R-180/180/-30/30 -JQ0/10c -fg "-A-15,+t$tag.txt" -GD5000k -W2p,magenta -P > "$tag.ps"
  "${AWK:-awk}" -v tag="$tag" 'FNR==NR {want[++nr]=$1;next} NF>=4 {n++;e=$1-want[n];if(e<0)e=-e;if(n>5||e>0.002||($2+15)^2>1e-6)bad=1;printf "%s label=%d lon=%.9f expected=%.9f\n",tag,n,$1,want[n]} END {printf "%s count=%d\n",tag,n;exit !(nr==5&&n==5&&!bad)}' distance-expected.xy "$tag.txt"
  "${AWK:-awk}" -v tag="$tag" '
    /%%BeginObject PSL_Layer_1/ {body=1}
    body && NF==3 && $3=="M" && $1 ~ /^-?[0-9]+$/ && $2==197 {x=$1;lo=hi=x;found=1;next}
    body && found && NF==3 && $3=="D" && $1 ~ /^-?[0-9]+$/ && $2==0 {x+=$1;if(x<lo)lo=x;if(x>hi)hi=x}
    END {printf "%s path=[%d,%d] expected=[1148,4593]\n",tag,lo,hi;exit !(found&&lo==1148&&hi==4593)}' "$tag.ps"
done

# Exercise normal growth beyond the initial 64 label slots, both with plot
# distance and with a geographic-distance sampling cache on one long segment.
gmt pscontour triangle.xyz -R-180/180/-30/30 -JQ0/10c -fg '-A-15,+f1p,Helvetica,black+tlabels-growth-plot.txt' -Gd0.05c -W2p,magenta -P > growth-plot.ps
"${AWK:-awk}" 'NF>=4 {n++;want=170-1.8*n;if(($1-want)^2>1e-6||($2+15)^2>1e-6)bad=1} END {printf "growth plot labels=%d\n",n;exit !(n==145&&!bad)}' labels-growth-plot.txt
"${AWK:-awk}" 'NR>1 {while($3>=200*(n+1)){n++;f=(200*n-pd)/($3-pd);printf "%.16g -15\n",px+f*($1-px)}} {px=$1;pd=$3} END {if(n<128)exit 1}' distance-km.tsv > distance-growth-expected.xy
gmt pscontour triangle.xyz -R-180/180/-30/30 -JQ0/10c -fg '-A-15,+f1p,Helvetica,black+tlabels-growth-map.txt' -GD200k -W2p,magenta -P > growth-map.ps
"${AWK:-awk}" 'FNR==NR {want[++nr]=$1;next} NF>=4 {n++;if(($1-want[n])^2>0.000004||($2+15)^2>1e-6)bad=1} END {printf "growth map labels=%d expected=%d\n",n,nr;exit !(n==nr&&n>=128&&!bad)}' distance-growth-expected.xy labels-growth-map.txt

# The inverse-projected Mercator line has a non-linear distance parameter.
# The expected positions use independent inverse-projection and 4096-interval
# mapproject -G+uk+a sampling; a linear fraction of total length is not enough.
printf '170 -65 -30\n170 65 30\n-175 -10 -30\n' > nonlinear.xyz
fmt=--FORMAT_FLOAT_OUT=%.16g
R=-R-180/180/-70/70
J=-JM0/10c
gmt mapproject nonlinear.xyz "$R" "$J" -fg -Di "$fmt" > vertices.xy
"${AWK:-awk}" 'NR==1 {ax=$1;ay=$2} NR==2 {bx=$1;by=$2} NR==3 {printf "%.16g %.16g\n%.16g %.16g\n",.75*ax+.25*bx,.75*ay+.25*by,.75*$1+.25*bx,.75*$2+.25*by}' vertices.xy > endpoints.xy
"${AWK:-awk}" 'NR==1{x=$1;y=$2} NR==2{for(i=0;i<=12;i++){xx=x+i*($1-x)/12;yy=y+i*($2-y)/12;printf "%.16g %.16g -16\n%.16g %.16g -14\n",xx,yy-.065,xx,yy+.065}}' endpoints.xy > nonlinear-dense-inches.xyz
"${AWK:-awk}" 'BEGIN{for(i=0;i<12;i++){j=2*i;print j,j+1,j+2;print j+1,j+3,j+2}}' > nonlinear-dense.tri
gmt mapproject nonlinear-dense-inches.xyz "$R" "$J" -I -Di "$fmt" > nonlinear-dense.xyz
"${AWK:-awk}" 'NR==1{x=$1;y=$2} NR==2{for(i=0;i<=4096;i++)printf "%.16g %.16g\n",x+i*($1-x)/4096,y+i*($2-y)/4096}' endpoints.xy > nonlinear-samples.xy
gmt mapproject nonlinear-samples.xy "$R" "$J" -I -Di "$fmt" > nonlinear-lonlat.xy
gmt mapproject nonlinear-lonlat.xy -G+uk+a -je -fg "$fmt" > nonlinear-distance.tsv
for mesh in sparse dense; do
  if [ "$mesh" = sparse ]; then args=(nonlinear.xyz); else args=(nonlinear-dense.xyz -Enonlinear-dense.tri); fi
  gmt pscontour "${args[@]}" "$R" "$J" -fg -C-15, "-A-15,+t$mesh-nonlinear.txt" -GD5000k -W2p,magenta -P "$fmt" > "$mesh-nonlinear.ps"
  gmt mapproject "$mesh-nonlinear.txt" "$R" "$J" -fg -Di "$fmt" > "$mesh-nonlinear-projected.txt"
  "${AWK:-awk}" -v tag="$mesh" '
    FILENAME==ARGV[1] {if(FNR==1){x=$1;y=$2}else{dx=$1-x;dy=$2-y;den=dx*dx+dy*dy}next}
    FILENAME==ARGV[2] {dist[++nr]=$3;next}
    FILENAME==ARGV[3] && NF>=4 {n++;f=(($1-x)*dx+($2-y)*dy)/den;k=int(f*4096)+1;if(k<1||k>=nr){bad=1;next}along=dist[k]+(f*4096-int(f*4096))*(dist[k+1]-dist[k]);err=along-5000*n;if(err<0)err=-err;if(err>0.05||($1-x-f*dx)^2+($2-y-f*dy)^2>1e-10)bad=1;printf "%s nonlinear label=%d distance=%.6f error=%.6f\n",tag,n,along,err}
    END {printf "%s nonlinear count=%d\n",tag,n;exit !(n==5&&nr==4097&&!bad)}' endpoints.xy nonlinear-distance.tsv "$mesh-nonlinear-projected.txt"
  "${AWK:-awk}" -v tag="$mesh" '
    /PSL_path_pen [0-9]+ get cvx exec/ {armed=1;next}
    armed && NF==3 && $3=="M" {x=$1;y=$2;next}
    armed && NF==3 && $3=="D" {n++;if(x!=4593||y!=736||x+$1!=1198||y+$2!=1484)bad=1;armed=0}
    END {printf "%s nonlinear projected paths=%d\n",tag,n;exit !(n>0&&!bad)}' "$mesh-nonlinear.ps"
done

# Check +LD with placement and label distances in independent units, including
# the documented default degrees and inherited units for map-distance spacing.
total_km=$("${AWK:-awk}" 'END {print $3}' distance-km.tsv)
total_deg=$("${AWK:-awk}" 'END {print $3}' distance-deg.tsv)
for item in 'GN-k -Gn1 -A-15,+LDk+tGN-k.txt' 'GN-n -Gn1 -A-15,+LDn+tGN-n.txt' 'GN-default -Gn1 -A-15,+LD+tGN-default.txt' 'GL-k -Gl0/-30/0/30 -A-15,+LDk+tGL-k.txt' 'GD-n -GD5000k -A-15,+LDn+tGD-n.txt' 'GD-inherit -GD5000k -A-15,+LD+tGD-inherit.txt' 'Gd-k -Gd2c -A-15,+LDk+tGd-k.txt' 'GD-nautical -GD5000n -A-15,+LDk+tGD-nautical.txt'; do
  read -r tag opt annot <<< "$item"
  gmt pscontour triangle.xyz -R-180/180/-30/30 -JQ0/10c -fg "$annot" "$opt" -W2p,magenta -P > "$tag.ps"
  "${AWK:-awk}" -v tag="$tag" -v total="$total_km" -v degrees="$total_deg" 'NF>=4 {n++;want=0;lon=$1;if(tag=="GN-k")want=total/2;else if(tag=="GN-n")want=total/2/1.852;else if(tag=="GN-default")want=degrees/2;else if(tag=="GL-k")want=total*170/262.5;else if(tag=="GD-n")want=n*5000/1.852;else if(tag=="GD-inherit")want=n*5000;else if(tag=="Gd-k")want=total*(170-lon)/262.5;else if(tag=="GD-nautical")want=n*5000*1.852;err=$4-want;if(err<0)err=-err;if(err>0.05||($2+15)^2>1e-6)bad=1;printf "%s value=%g expected=%g lon=%.9f\n",tag,$4,want,lon} END {expected=(tag=="GD-n"||tag=="GD-inherit")?5:((tag=="Gd-k"||tag=="GD-nautical")?3:1);printf "%s count=%d expected=%d\n",tag,n,expected;exit !(n==expected&&!bad)}' "$tag.txt"
done

gmt pscontour triangle.xyz -R-180/180/-30/30 -JQ0/10c -fg '-A-15,+LD+tangular.txt' -GD30d -W2p,magenta -P > angular.ps
"${AWK:-awk}" -v degrees="$total_deg" 'NF>=4 {n++;want=170-262.5*n*30/degrees;if(($1-want)^2>0.000004||($2+15)^2>1e-6||($4-n*30)^2>1e-8)bad=1} END {printf "angular inherited values count=%d\n",n;exit !(n==8&&!bad)}' angular.txt

# A closed diamond checks both cumulative distance through corners and the
# +r curvature filter.  Independently inverse-project sampled segments before
# measuring with mapproject, then interpolate each expected 1000 km position.
printf '0 0 0\n-60 0 20\n0 30 20\n60 0 20\n0 -30 20\n' > diamond.xyz
R=-R-80/80/-50/50
J=-JQ0/10c
gmt pscontour diamond.xyz "$R" "$J" -fg -C10, -A- -D "$fmt" > closed-dump.xy
"${AWK:-awk}" '$1 !~ /^>/ && NF>=2 {n++;x[n]=$1;y[n]=$2} END {printf "closed dump vertices=%d\n",n;exit !(n==5&&(x[1]-x[n])^2<1e-10&&(y[1]-y[n])^2<1e-10)}' closed-dump.xy
gmt mapproject closed-dump.xy "$R" "$J" -fg -Di "$fmt" > closed-projected.xy
for kind in normal curve; do
  first=1;opt='-A10,+tlabels-normal.txt'
  if [ "$kind" = curve ]; then first=4;opt='-A10,+r1000c+tlabels-curve.txt';fi
  "${AWK:-awk}" -v first="$first" '$1 !~ /^>/ && NF>=2 {n++;x[n]=$1;y[n]=$2} END {if(n!=5)exit 1;for(i=first;i<5;i++)for(k=(i==first?0:1);k<=1024;k++)printf "%.16g %.16g\n",x[i]+k*(x[i+1]-x[i])/1024,y[i]+k*(y[i+1]-y[i])/1024}' closed-projected.xy > "$kind-samples.xy"
  gmt mapproject "$kind-samples.xy" "$R" "$J" -I -Di "$fmt" > "$kind-geo.xy"
  gmt mapproject "$kind-geo.xy" -G+uk+a -je -fg "$fmt" > "$kind-dist.xyz"
  gmt pscontour diamond.xyz "$R" "$J" -fg -C10, "$opt" -GD1000k -W2p,magenta -P > "$kind-closed.ps"
  "${AWK:-awk}" -v tag="$kind" 'FNR==NR {if(FNR>1)while($3>=1000*(m+1)){m++;f=(1000*m-pd)/($3-pd);ex[m]=px+f*($1-px);ey[m]=py+f*($2-py)}px=$1;py=$2;pd=$3;next} NF>=4 {n++;dx=$1-ex[n];dy=$2-ey[n];if(dx*dx>0.000004||dy*dy>0.000004)bad=1} END {printf "%s closed count=%d expected=%d\n",tag,n,m;exit !(n==m&&n>0&&!bad)}' "$kind-dist.xyz" "labels-$kind.txt"
done
