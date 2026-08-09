
template
{
    name = "skeleton_drawing_bom";
    type = GRAPHICAL;
    width = 180;
    maxheight = 10000;
    columns = (1, 1);
    gap = 1;
    fillpolicy = EVEN;
    filldirection = HORIZONTAL;
    fillstartfrom = TOPLEFT;
    margins = (0, 0, 0, 0);
    gridxspacing = 1;
    gridyspacing = 1;
    version = 5.2;
    created = "01.01.2025 00:00";
    modified = "01.01.2025 00:00";
    notes = "Drawing-embedded BOM: CURRENT_DRAWING filter on every data row; PART+REBAR sibling sections; mm layout, no columns.";
    colors = "153;152;160;161;162;163;164;165;154;155;156;157;158;159;130;131;132;133;";
    usepagebreaks = TRUE;

    header
    {
        name = "HEADER";
        height = 11;

        text
        {
            name = "title";
            x1 = 2;
            y1 = 6;
            x2 = 2;
            y2 = 6;
            string = "BILL OF MATERIAL";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 3.5;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };

        text
        {
            name = "cap_pos";
            x1 = 2;
            y1 = 1;
            x2 = 2;
            y2 = 1;
            string = "Pos";
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
        text
        {
            name = "cap_prof";
            x1 = 22;
            y1 = 1;
            x2 = 22;
            y2 = 1;
            string = "Profile / Size";
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
        text
        {
            name = "cap_grade";
            x1 = 54;
            y1 = 1;
            x2 = 54;
            y2 = 1;
            string = "Grade";
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
        text
        {
            name = "cap_len";
            x1 = 80;
            y1 = 1;
            x2 = 80;
            y2 = 1;
            string = "Length";
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
        text
        {
            name = "cap_qty";
            x1 = 107;
            y1 = 1;
            x2 = 107;
            y2 = 1;
            string = "Qty";
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
        text
        {
            name = "cap_wt";
            x1 = 131;
            y1 = 1;
            x2 = 131;
            y2 = 1;
            string = "Weight kg";
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

        lineorarc
        {
            name = "hdr_top";
            x1 = 0;
            y1 = 11;
            x2 = 180;
            y2 = 11;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 2;
            bulge = 0;
        };
        lineorarc
        {
            name = "hdr_bot";
            x1 = 0;
            y1 = 0;
            x2 = 180;
            y2 = 0;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 1;
            bulge = 0;
        };
    };

    row _tmp_steel_head
    {
        name = "STEEL_heading";
        height = 4;
        visibility = TRUE;
        usecolumns = FALSE;
        rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") && GetValue(\"MATERIAL_TYPE\") != \"CONCRETE\" then\n  Output()\nelse\n  StepOver()\nendif";
        contenttype = "PART";
        sorttype = COMBINE;

        text
        {
            name = "steel_label";
            x1 = 2;
            y1 = 1;
            x2 = 2;
            y2 = 1;
            string = "STEEL";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
    };

    row _tmp_steel_detail
    {
        name = "STEEL_detail";
        height = 4;
        visibility = TRUE;
        usecolumns = FALSE;
        rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") && GetValue(\"MATERIAL_TYPE\") != \"CONCRETE\" then\n  Output()\nelse\n  StepOver()\nendif";
        contenttype = "PART";
        sorttype = COMBINE;

        valuefield
        {
            name = "STEEL_POS";
            location = (2, 1);
            formula = "GetValue(\"PART_POS\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 11;
            sortdirection = ASCENDING;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        valuefield
        {
            name = "STEEL_PROFILE";
            location = (22, 1);
            formula = "GetValue(\"PROFILE\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 18;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        valuefield
        {
            name = "STEEL_GRADE";
            location = (54, 1);
            formula = "GetValue(\"MATERIAL\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 10;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        valuefield
        {
            name = "STEEL_LENGTH";
            location = (80, 1);
            formula = "if GetValue(\"ADVANCED_OPTION.XS_IMPERIAL\")==\"TRUE\" then\nformat(GetValue(\"LENGTH\"),\"Length\",\"inch-frac\", 1/16)\nelse\nformat(round(GetValue(\"LENGTH\"), 5),\"Length\",\"mm\", 0)\nendif";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 14;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        valuefield
        {
            name = "STEEL_QTY";
            location = (107, 1);
            formula = "GetValue(\"NUMBER\")";
            datatype = INTEGER;
            class = "";
            cacheable = TRUE;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 12;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = SUM;
        };
        valuefield
        {
            name = "PART_WEIGHT";
            location = (131, 1);
            formula = "GetValue(\"WEIGHT\")";
            datatype = DOUBLE;
            class = "Weight";
            cacheable = TRUE;
            decimals = 1;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 16;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = SUM;
            unit = "kg";
        };
    };

    row _tmp_steel_sum
    {
        name = "STEEL_summary";
        height = 5;
        visibility = TRUE;
        usecolumns = FALSE;
        rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") && GetValue(\"MATERIAL_TYPE\") != \"CONCRETE\" then\n  Output()\nelse\n  StepOver()\nendif";
        contenttype = "PART";
        sorttype = COMBINE;

        text
        {
            name = "steel_sum_label";
            x1 = 109;
            y1 = 2;
            x2 = 109;
            y2 = 2;
            string = "Steel subtotal";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "STEEL_SUBTOTAL";
            location = (131, 2);
            formula = "GetValue(\"WEIGHT\")";
            datatype = DOUBLE;
            class = "Weight";
            cacheable = TRUE;
            decimals = 1;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 16;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = SUM;
            unit = "kg";
        };
        lineorarc
        {
            name = "steel_rule";
            x1 = 98;
            y1 = 0;
            x2 = 180;
            y2 = 0;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 1;
            bulge = 0;
        };
    };

    row _tmp_rebar_head
    {
        name = "REBAR_heading";
        height = 4;
        visibility = TRUE;
        usecolumns = FALSE;
        rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") && GetValue(\"CLASS\") != 100 then\n  Output()\nelse\n  StepOver()\nendif";
        contenttype = "REBAR";
        sorttype = COMBINE;

        text
        {
            name = "rebar_label";
            x1 = 2;
            y1 = 1;
            x2 = 2;
            y2 = 1;
            string = "REINFORCEMENT";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
    };

    row _tmp_rebar_detail
    {
        name = "REBAR_detail";
        height = 4;
        visibility = TRUE;
        usecolumns = FALSE;
        rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") && GetValue(\"CLASS\") != 100 then\n  Output()\nelse\n  StepOver()\nendif";
        contenttype = "REBAR";
        sorttype = COMBINE;

        valuefield
        {
            name = "REBAR_POS";
            location = (2, 1);
            formula = "GetValue(\"REBAR_POS\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 11;
            sortdirection = ASCENDING;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        valuefield
        {
            name = "REBAR_SIZE";
            location = (22, 1);
            formula = "GetValue(\"SIZE\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 18;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        valuefield
        {
            name = "REBAR_GRADE";
            location = (54, 1);
            formula = "GetValue(\"GRADE\")";
            datatype = STRING;
            class = "";
            cacheable = TRUE;
            justify = LEFT;
            visibility = TRUE;
            angle = 0;
            length = 10;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
        };
        valuefield
        {
            name = "REBAR_LENGTH";
            location = (80, 1);
            formula = "GetValue(\"LENGTH\")";
            datatype = DOUBLE;
            class = "Length";
            cacheable = TRUE;
            decimals = 0;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 14;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = NONE;
            unit = "mm";
        };
        valuefield
        {
            name = "REBAR_QTY";
            location = (107, 1);
            formula = "GetValue(\"NUMBER\")";
            datatype = INTEGER;
            class = "";
            cacheable = TRUE;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 12;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = SUM;
        };
        valuefield
        {
            name = "REBAR_WEIGHT";
            location = (131, 1);
            formula = "GetValue(\"WEIGHT\")";
            datatype = DOUBLE;
            class = "Weight";
            cacheable = TRUE;
            decimals = 1;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 16;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = SUM;
            unit = "kg";
        };
    };

    row _tmp_rebar_sum
    {
        name = "REBAR_summary";
        height = 5;
        visibility = TRUE;
        usecolumns = FALSE;
        rule = "if GetValue(\"ASSEMBLY.HIERARCHY_LEVEL\") == GetValue(\"CURRENT_DRAWING.ASSEMBLY.HIERARCHY_LEVEL\") && GetValue(\"CLASS\") != 100 then\n  Output()\nelse\n  StepOver()\nendif";
        contenttype = "REBAR";
        sorttype = COMBINE;

        text
        {
            name = "rebar_sum_label";
            x1 = 109;
            y1 = 2;
            x2 = 109;
            y2 = 2;
            string = "Rebar subtotal";
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontslant = 0;
            fontstyle = 0;
            angle = 0;
            justify = LEFT;
            pen = 0;
        };
        valuefield
        {
            name = "REBAR_SUBTOTAL";
            location = (131, 2);
            formula = "GetValue(\"WEIGHT\")";
            datatype = DOUBLE;
            class = "Weight";
            cacheable = TRUE;
            decimals = 1;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 16;
            sortdirection = NONE;
            fontname = "Arial";
            fontcolor = 153;
            fonttype = 2;
            fontsize = 2.5;
            fontratio = 1;
            fontstyle = 0;
            fontslant = 0;
            pen = 0;
            oncombine = SUM;
            unit = "kg";
        };
        lineorarc
        {
            name = "rebar_rule";
            x1 = 98;
            y1 = 0;
            x2 = 180;
            y2 = 0;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 1;
            bulge = 0;
        };
    };

    footer
    {
        name = "FOOTER";
        height = 8;

        lineorarc
        {
            name = "foot_top";
            x1 = 0;
            y1 = 7;
            x2 = 180;
            y2 = 7;
            pen = 0;
            color = 153;
            linetype = 1;
            linewidth = 2;
            bulge = 0;
        };
        text
        {
            name = "total_label";
            x1 = 99;
            y1 = 2;
            x2 = 99;
            y2 = 2;
            string = "TOTAL WEIGHT (kg):";
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
        valuefield
        {
            name = "GRAND_TOTAL";
            location = (131, 2);
            formula = "Sum(\"PART_WEIGHT\")+Sum(\"REBAR_WEIGHT\")";
            datatype = DOUBLE;
            class = "Weight";
            cacheable = TRUE;
            decimals = 1;
            justify = RIGHT;
            visibility = TRUE;
            angle = 0;
            length = 13;
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
            unit = "kg";
        };
    };
};
