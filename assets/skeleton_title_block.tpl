
template
{
    name = "skeleton_title_block";
    type = GRAPHICAL;
    width = 180;
    maxheight = 120;
    columns = (1, 1);
    gap = 1;
    fillpolicy = EVEN;
    filldirection = HORIZONTAL;
    fillstartfrom = TOPLEFT;
    margins = (0, 0, 0, 0);
    gridxspacing = 1;
    gridyspacing = 0.5;
    version = 4.2;
    created = "01.01.2025 00:00";
    modified = "01.01.2025 00:00";
    notes = "Title block: ONE DRAWING row holds all fields, labels, frame lines. usecolumns=FALSE, COMBINE; text y anchors BOTTOM.";
    colors = "153;152;160;161;162;163;164;165;154;155;156;157;158;159;130;131;132;133;";

    row _tmp_0
    {
        name = "DRAWING";
        height = 36;
        visibility = TRUE;
        usecolumns = FALSE;
        rule = "";
        contenttype = "DRAWING";
        sorttype = COMBINE;

        lineorarc
        {
            name = "frame_b";
            x1 = 0;
            y1 = 0;
            x2 = 180;
            y2 = 0;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 2;
            bulge = 0;
        };
        lineorarc
        {
            name = "frame_t";
            x1 = 0;
            y1 = 36;
            x2 = 180;
            y2 = 36;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 2;
            bulge = 0;
        };
        lineorarc
        {
            name = "frame_l";
            x1 = 0;
            y1 = 0;
            x2 = 0;
            y2 = 36;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 2;
            bulge = 0;
        };
        lineorarc
        {
            name = "frame_r";
            x1 = 180;
            y1 = 0;
            x2 = 180;
            y2 = 36;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 2;
            bulge = 0;
        };
        lineorarc
        {
            name = "div_h1";
            x1 = 0;
            y1 = 12;
            x2 = 180;
            y2 = 12;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 1;
            bulge = 0;
        };
        lineorarc
        {
            name = "div_h2";
            x1 = 0;
            y1 = 24;
            x2 = 180;
            y2 = 24;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 1;
            bulge = 0;
        };
        lineorarc
        {
            name = "div_v";
            x1 = 120;
            y1 = 0;
            x2 = 120;
            y2 = 36;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 1;
            bulge = 0;
        };

        text
        {
            name = "lbl_project";
            x1 = 2;
            y1 = 32;
            x2 = 2;
            y2 = 32;
            string = "PROJECT";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "PROJECT_NAME";
            location = (2, 26);
            formula = "GetValue(\"PROJECT.NAME\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 50;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };

        text
        {
            name = "lbl_title";
            x1 = 2;
            y1 = 20;
            x2 = 2;
            y2 = 20;
            string = "DRAWING TITLE";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "TITLE1";
            location = (2, 14);
            formula = "GetValue(\"TITLE1\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 44;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 4;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };

        text
        {
            name = "lbl_drawn";
            x1 = 2;
            y1 = 8;
            x2 = 2;
            y2 = 8;
            string = "DRAWN BY";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "DRAWN_BY";
            location = (2, 2);
            formula = "GetValue(\"REVISION.LAST_CREATED_BY\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 24;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        text
        {
            name = "lbl_date";
            x1 = 62;
            y1 = 8;
            x2 = 62;
            y2 = 8;
            string = "DATE";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "PLOT_DATE";
            location = (62, 2);
            formula = "GetValue(\"DATE_PLOT\")";
            datatype = INTEGER;
            class = "Date";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 20;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
            unit = "dd.mm.yyyy";
        };

        text
        {
            name = "lbl_dwgno";
            x1 = 122;
            y1 = 32;
            x2 = 122;
            y2 = 32;
            string = "DWG No";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "DWG_NUMBER";
            location = (122, 26);
            formula = "GetValue(\"NAME\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 21;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 4;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };

        text
        {
            name = "lbl_scale";
            x1 = 122;
            y1 = 20;
            x2 = 122;
            y2 = 20;
            string = "SCALE";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "SCALE";
            location = (122, 14);
            formula = "GetValue(\"SCALE1\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 12;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        text
        {
            name = "lbl_size";
            x1 = 152;
            y1 = 20;
            x2 = 152;
            y2 = 20;
            string = "SIZE";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "SIZE";
            location = (152, 14);
            formula = "GetValue(\"SIZE\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 12;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };

        text
        {
            name = "lbl_rev";
            x1 = 122;
            y1 = 8;
            x2 = 122;
            y2 = 8;
            string = "REV";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "REVISION";
            location = (140, 2);
            formula = "GetValue(\"REVISION.LAST_MARK\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 12;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 4;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
    };
};
