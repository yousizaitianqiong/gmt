#!/usr/bin/env bash
# Compare projected-contour label locations with the configured GMT distance model.
# All paths are legal, non-wrapping and sampled independently with mapproject.
# Run under GMT's gmtest wrapper, which supplies optional shell variables.
AWK=${AWK:-awk}
fmt=--FORMAT_FLOAT_OUT=%.16g
printf '%s\n' '-6 32' '7 59' > model-endpoints.xy
fail=0
for spec in 'merc WGS-84 Vincenty e' 'merc WGS-84 Andoyer e' 'eqc WGS-84 Vincenty e' 'eqc WGS-84 Andoyer e' 'merc Sphere Vincenty g' 'eqc Sphere Vincenty g' 'merc FlatEarth Vincenty f'; do
  read -r proj ellipsoid geodesic expected <<< "$spec"
  tag="$proj-$ellipsoid-$geodesic"
  mkdir "$tag"
  (
    cd "$tag" || exit 1
    R=-R-20/20/20/70
    if [ "$proj" = merc ]; then J=-JM0/12c; else J=-JQ0/12c; fi
    settings=("--PROJ_ELLIPSOID=$ellipsoid" "--PROJ_GEODESIC=$geodesic")
    gmt mapproject ../model-endpoints.xy "$R" "$J" "${settings[@]}" -Di -fg "$fmt" > endpoints.xy 2> endpoints.err || exit 1
    "$AWK" 'NR==1{x=$1;y=$2} NR==2{for(i=0;i<=512;i++){f=i/512;X=x+f*($1-x);Y=y+f*($2-y);printf "%.16g %.16g -1\n%.16g %.16g 1\n",X,Y-.025,X,Y+.025}}' endpoints.xy > dense-inches.xyz
    "$AWK" 'BEGIN{for(i=0;i<512;i++){j=2*i;print j,j+1,j+2;print j+1,j+3,j+2}}' > dense.tri
    "$AWK" 'NR==1{x=$1;y=$2} NR==2{for(i=0;i<=4096;i++){f=i/4096;printf "%.16g %.16g %.16g\n",x+f*($1-x),y+f*($2-y),f}}' endpoints.xy > samples-inches.xyt
    gmt mapproject dense-inches.xyz "$R" "$J" "${settings[@]}" -I -Di "$fmt" > dense.xyz 2> dense.err || exit 1
    gmt mapproject samples-inches.xyt "$R" "$J" "${settings[@]}" -I -Di "$fmt" > samples.xyt 2> samples.err || exit 1
    for mode in f g e; do
      gmt mapproject samples.xyt "${settings[@]}" -G+uk+a "-j$mode" -fg "$fmt" > "reference-$mode.tsv" 2> "reference-$mode.err" || exit 1
    done
    gmt pscontour dense.xyz -Edense.tri "$R" "$J" "${settings[@]}" -fg -C0, -A- -D "$fmt" > contour.xy 2> dump.err || exit 1
    gmt mapproject contour.xy "$R" "$J" "${settings[@]}" -Di -fg "$fmt" > contour-projected.xy 2> contour-project.err || exit 1
    "$AWK" 'FNR==NR{if(FNR==1){x=$1;y=$2}else{dx=$1-x;dy=$2-y;den=dx*dx+dy*dy}next} $1!~/^>/ && NF>=2{f=(($1-x)*dx+($2-y)*dy)/den;ex=x+f*dx;ey=y+f*dy;if(($1-ex)^2+($2-ey)^2>1e-12)bad=1;if(n==0||f<lo)lo=f;if(n==0||f>hi)hi=f;n++} END{printf "dump points=%d fraction=[%.9f,%.9f]\n",n,lo,hi;exit !(n>=2&&!bad&&lo<0.000001&&hi>0.999999)}' endpoints.xy contour-projected.xy || exit 1
    gmt pscontour dense.xyz -Edense.tri "$R" "$J" "${settings[@]}" -fg -C0, '-A0,+tlabels.txt' -GD400k -W1p -P -Vd "$fmt" > contour.ps 2> draw.err || exit 1
    gmt mapproject labels.txt "$R" "$J" "${settings[@]}" -Di -fg "$fmt" > labels-projected.txt 2> label-project.err || exit 1
    "$AWK" -v tag="$tag" '
      FILENAME==ARGV[1]{if(FNR==1){x=$1;y=$2}else{dx=$1-x;dy=$2-y;den=dx*dx+dy*dy}next}
      FILENAME==ARGV[2]{nref++;d[nref]=$4;next}
      FILENAME==ARGV[3] && NF>=4 {n++;f=(($1-x)*dx+($2-y)*dy)/den;pos=f*4096;k=int(pos)+1;if(k<1||k>=nref){bad=1;next}actual=d[k]+(pos-int(pos))*(d[k+1]-d[k]);err=actual-400*n;if(err<0)err=-err;if(err>0.002)bad=1;printf "%s label=%d fraction=%.9f distance=%.6f km error=%.6f km\n",tag,n,f,actual,err}
      END {printf "%s labels=%d samples=%d\n",tag,n,nref;exit !(n==7&&nref==4097&&!bad)}' endpoints.xy "reference-$expected.tsv" labels-projected.txt || exit 1
    case "$expected:$geodesic" in
      f:*) want='Flat Earth';;
      g:*) want='great circle approximation';;
      e:Vincenty) want='Vincenty geodesics';;
      e:Andoyer) want='Andoyer geodesics';;
    esac
    "$AWK" -v want="$want" '/Contour distance calculation will be/{last=$0} END{print "actual final model: " last;if(index(last,want)==0)exit 1}' draw.err || exit 1
  )
  code=$?
  printf '%s exit=%s\n' "$tag" "$code"
  if [ "$code" != 0 ]; then fail=1; fi
done
for proj in merc eqc; do
  a="$proj-WGS-84-Vincenty/labels.txt"
  b="$proj-WGS-84-Andoyer/labels.txt"
  if [ ! -s "$a" ] || [ ! -s "$b" ] || cmp -s "$a" "$b"; then
    printf '%s Vincenty/Andoyer sensitivity FAIL\n' "$proj"
    fail=1
  else
    printf '%s Vincenty/Andoyer labels differ\n' "$proj"
  fi
done
# Return the aggregate status to a caller that sources this script (gmtest).
(exit "$fail")
