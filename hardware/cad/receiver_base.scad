// Spontaan R1 receiver carrier. Units: mm. Board is bought, not printed.
// Raspberry Pi Zero 2 W: 65 x 30; mounting centres 58 x 23.
// Source: official mechanical drawing linked in ../README.md.
$fn = 48;
plate_x = 95;
plate_y = 60;
plate_z = 3;
stand_height = 6;
board_x = 65;
board_y = 30;
board_origin = [15, 15];
hole_d = 2.8; // M2.5 clearance, through carrier and stand.
show_board = false;

module rounded_plate(x, y, z, r=4) {
  hull() for (px=[r,x-r], py=[r,y-r])
    translate([px,py,0]) cylinder(h=z,r=r);
}
module mount_slot(x,y) {
  hull() for (dx=[-2.5,2.5])
    translate([x+dx,y,-1]) cylinder(h=plate_z+2,d=3.5);
}

difference() {
  union() {
    rounded_plate(plate_x,plate_y,plate_z);
    for (x=[3.5,61.5], y=[3.5,26.5])
      translate([board_origin[0]+x,board_origin[1]+y,plate_z])
        cylinder(h=stand_height,d=6.5);
  }
  for (x=[3.5,61.5], y=[3.5,26.5])
    translate([board_origin[0]+x,board_origin[1]+y,-1])
      cylinder(h=plate_z+stand_height+2,d=hole_d);
  for (x=[8,plate_x-8],y=[6,plate_y-6]) mount_slot(x,y);
}

if (show_board)
  %translate([board_origin[0],board_origin[1],plate_z+stand_height])
    color("seagreen") cube([board_x,board_y,1.6]);
