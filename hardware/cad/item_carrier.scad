// Spontaan T1: carrier around an already sealed BLE tag, never a bare battery.
// Units: mm. Measure the chosen tag before setting these parameters.
$fn = 64;
part = "both"; // body | lid | both
tag_d = 30;
tag_h = 9;
clearance = 0.6; // radial clearance; printer fit is checked with a dummy.
wall = 2;
base = 3;
lid_z = 2;
inner_d = tag_d + 2*clearance;
outer_d = inner_d + 2*wall;
body_h = base + tag_h + clearance;
post_y = outer_d/2 + 2.4;
plate_x = outer_d + 22.8;
plate_y = 2*(post_y+5);

module rounded_plate() {
  hull() for (x=[-plate_x/2+4,plate_x/2-4],y=[-plate_y/2+4,plate_y/2-4])
    translate([x,y,0]) cylinder(h=base,r=4);
}
module cap_shape(h) {
  union() {
    cylinder(h=h,d=outer_d);
    for (y=[-post_y,post_y])
      hull() {
        translate([0,y,0]) cylinder(h=h,d=6);
        translate([0,y>0?outer_d/2-2:-outer_d/2+2,0]) cylinder(h=h,d=6);
      }
  }
}
module screw_holes(h) {
  for (y=[-post_y,post_y]) translate([0,y,-1]) cylinder(h=h+2,d=2.5);
}
module body() {
  difference() {
    union() { rounded_plate(); cap_shape(body_h); }
    translate([0,0,base]) cylinder(h=body_h+1,d=inner_d);
    screw_holes(body_h);
    for (x=[-plate_x/2+5,plate_x/2-5])
      translate([x-1.5,-10.5,-1]) cube([3,21,base+2]);
  }
}
module lid() { difference() { cap_shape(lid_z); screw_holes(lid_z); } }

if (part=="body" || part=="both") body();
if (part=="lid") lid();
if (part=="both") translate([plate_x+8,0,0]) lid();
