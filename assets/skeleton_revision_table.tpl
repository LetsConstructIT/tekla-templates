
template
{
    name = "skeleton_revision_table";
    type = GRAPHICAL;
    width = 160;
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
    notes = "Revision table: hidden DRAWING wrapper row + nested REVISION row (MARK, DESCRIPTION, DATE_CREATE). usecolumns=FALSE.";
    colors = "153;152;160;161;162;163;164;165;154;155;156;157;158;159;130;131;132;133;";

    header _tmp_h
    {
        name = "Header";
        height = 6;

        lineorarc
        {
            name = "TopLine";
            x1 = 0;
            y1 = 0;
            x2 = 160;
            y2 = 0;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 2;
            bulge = 0;
        };
        text
        {
            name = "hdr_rev";
            x1 = 2;
            y1 = 1;
            x2 = 2;
            y2 = 1;
            string = "Rev";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        text
        {
            name = "hdr_desc";
            x1 = 30;
            y1 = 1;
            x2 = 30;
            y2 = 1;
            string = "Description";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        text
        {
            name = "hdr_date";
            x1 = 130;
            y1 = 1;
            x2 = 130;
            y2 = 1;
            string = "Date";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        lineorarc
        {
            name = "BottomLine";
            x1 = 0;
            y1 = 5;
            x2 = 160;
            y2 = 5;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 1;
            bulge = 0;
        };
    };

    row _tmp_0
    {
        name = "DRAWING";
        height = 5;
        visibility = FALSE;
        usecolumns = FALSE;
        rule = "";
        contenttype = "DRAWING";
        sorttype = COMBINE;

        row _tmp_1
        {
            name = "REVISION";
            height = 5;
            visibility = TRUE;
            usecolumns = FALSE;
            rule = "";
            contenttype = "REVISION";
            sorttype = DISTINCT;

            valuefield
            {
                name = "REV_MARK";
                location = (2, 3);
                formula = "GetValue(\"MARK\")";
                datatype = STRING;
                class = "";
                cacheable = TRUE;
                justify = LEFT;
                visibility = TRUE;
                angle = 0;
                length = 6;
                sortdirection = ASCENDING;
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
            valuefield
            {
                name = "REV_DESC";
                location = (30, 3);
                formula = "GetValue(\"DESCRIPTION\")";
                datatype = STRING;
                class = "";
                cacheable = TRUE;
                justify = LEFT;
                visibility = TRUE;
                angle = 0;
                length = 49;
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
            valuefield
            {
                name = "REV_DATE";
                location = (130, 3);
                formula = "GetValue(\"DATE_CREATE\")";
                datatype = STRING;
                class = "";
                cacheable = TRUE;
                justify = LEFT;
                visibility = TRUE;
                angle = 0;
                length = 14;
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
        };
    };
};
