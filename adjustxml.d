module adjustxml;

import std.stdio;
import std.string : strip;
import std.uni;
import std.algorithm;
import std.range;
import std.typecons;
import std.conv;
import std.exception;

enum XMLType
{
    ELEMENT,
    TEXT
}

alias string XMLText;

struct XMLChild
{
private:

    union XMLValue
    {
        XMLElement* element;
        XMLText     text;
    }

    XMLValue value;

public:

    immutable XMLType type;

    this( XMLElement* element )
    {
        this.value.element = element;
        this.type = XMLType.ELEMENT;
    }

    this( string text )
    {
        this.value.text = text;
        this.type = XMLType.TEXT;
    }

    @property {
        XMLElement* element()
        {
            assert( this.type == XMLType.ELEMENT );
            return this.value.element;
        }

        XMLText text()
        {
            assert( this.type == XMLType.TEXT );
            return this.value.text;
        }
    }

}

struct XMLAttribute
{
    string name;
    string value;
}

struct XMLElement
{
private:
    XMLChild[] childs;

public:
    string tag;
    XMLAttribute[] attrs;

    void addChild( XMLChild child )
    {
        childs ~= child;
    }

    @property
    {
        XMLElement*[] elems()
        {
            return childs.filter!( a => a.type == XMLType.ELEMENT ).map!( b => b.element ).array;
        }

        XMLText[] texts()
        {
            return childs.filter!( a => a.type == XMLType.TEXT ).map!( b => b.text ).array;
        }

        string[] pretty( int depth = 0 )
        {

            // inner functions
            string indent() { return repeat( "    ", depth ).join; }

            string prettyAttrs()
            {
                string result;
                foreach( attr; attrs )
                    result ~= attr.name ~ "=\"" ~ attr.value ~ "\" ";
                return result[0..$-1];
            }

            //body
            string[] result;
            string line = indent ~ "<" ~ tag ~ " " ~ prettyAttrs;

            if( childs.empty )
            {
                result ~= line ~ " />";
            }
            else
            {
                result ~= line ~ ">";
                ++depth;

                foreach( child; childs )
                {
                    with( XMLType )
                    final switch( child.type )
                    {
                        case ELEMENT :
                        {
                            result ~= child.element.pretty( depth );
                        } break;
                        case TEXT :
                        {
                            result ~= indent ~ child.text;
                        } break;
                    }
                }

                --depth;
                result ~= indent ~ "</" ~ tag ~ ">";
            }

            return result;
        }

    }

}

struct XMLDocument
{
    XMLElement declXML;
    string     declDocType;
    XMLElement root;
}

XMLDocument parseXML(T)(T xml) if (isInputRange!T)
{

    XMLDocument doc;

    if( xml.empty ) return doc;

    dchar peekChar()
    {
        dchar result;
        if( xml.empty ) return '\0';
        result = xml.front;
        xml.popFront;
        return result;
    }

    void skipWhite()
    {
        while( !xml.empty && xml.front.isWhite ) peekChar;
    }

    void skip( int count )
    {
        for( int i = 0; i<count; ++i ) peekChar;
        skipWhite;
    }

    void declCheck()
    {
        while( true )
        {
            skipWhite;

            if( xml[0..2] == "<?" )
            {
                string name, value;
                bool flag = false;

                skip( 2 ); //eat "<?"

                while( xml.front != '?' )
                {
                    if( xml.front == ' ' )
                    {
                        if( flag )
                        {
                            doc.declXML.attrs ~= XMLAttribute( name, value[1..$-1] );
                            name = value = "";
                            flag = false;
                        }
                        else
                        {
                            doc.declXML.tag = name;
                            name = "";
                        }

                        skipWhite;
                    }
                    else if( xml.front == '=' )
                    {
                        flag = true;
                        peekChar;
                    }
                    else
                    {
                        ( flag ? value : name ) ~= peekChar;
                    }
                }

                skip( 2 ); //eat "?>"

            }
            else if( xml[0..2] == "<!" )
            {
                skip( 2 ); //eat "<!"

                string type;
                while( xml.front != '>' ) type ~= peekChar;
                doc.declDocType = type;

                skip( 1 ); //eat ">"
            }
            else
            {
                break;
            }
        }
        skipWhite;
    } //declCheck()
    
    void parseBody()
    {
        XMLElement result;
        alias Tuple!( XMLChild, bool )[] Stack;
        Stack stack;

        string text;

        void setText( string text )
        {
            stack ~= tuple( XMLChild( text ), true );
        }

        void writeChild( XMLChild child )
        {
            with( XMLType )
            final switch( child.type )
            {
                case ELEMENT : { writeln( child.element ); } break;
                case TEXT    : { writeln( child.text ); } break;
            }
        }

        while( !xml.empty )
        {
            if( xml[0..4] == "<!--")
            {
                // comment
            }
            else if( xml[0..2] == "</" )
            {
                if( !text.empty )
                {
                    setText( text.strip );
                    text = "";
                }
                skip( 2 ); // eat "</"

                string name;
                while( xml.front != '>' ) name ~= peekChar;
                name.strip;
                skip( 1 ); // eat ">"

                Stack childs;
                while( !stack.empty )
                {
                    if( (!stack.back[1]) && (stack.back[0].element.tag == name ) )
                    {
                        foreach( child; childs.retro )
                        {
                            stack.back[0].element.addChild( child[0] );
                        }
                        stack.back[1] = true;
                        childs = [];
                        break;
                    }
                    else
                    {
                        childs ~= stack.back;
                        stack.popBack;
                    }
                }

                assert( childs.empty );

                if( xml.empty )
                {
                    assert( stack.length == 1 );
                    assert( stack.front[1] );
                    doc.root = *(stack.front[0].element);
                    return;
                }
            }
            else if( xml[0] == '<' )
            {
                if( !text.empty )
                {
                    setText( text.strip );
                    text = "";
                }
                skip( 1 ); // eat "<"

                XMLElement* elem = new XMLElement();
                while( xml.front != ' ' && xml.front != '>' )
                    elem.tag ~= peekChar;

                if( xml.front == '>' )
                {
                    stack ~= tuple( XMLChild( elem ), false );
                    skip( 1 ); // eat ">"
                    continue;
                }

                string name;
                while( true )
                {
                    skipWhite;
                    if( xml.front == '=' ) //parse Attribute
                    {
                        peekChar;
                        assert( xml.front == '"' );
                        peekChar;

                        string value;
                        while( xml.front != '"' ) value ~= peekChar;
                        elem.attrs ~= XMLAttribute( name, value );

                        name = value = "";
                        skip( 1 ); // eat '"'
                    }
                    else if( xml.front == '>' )
                    {
                        stack ~= tuple( XMLChild( elem ), name == "/" );
                        skip( 1 ); // eat ">"
                        break;
                    }
                    else
                    {
                        name ~= peekChar;
                    }
                }
            }
            else
            {
                text ~= peekChar;
            }
        }
    }

    declCheck;
    parseBody;

    return doc;
}

unittest
{
    //static XMLDocument doc = parseXML( q{
    XMLDocument doc = parseXML( q{
        <?xml version="1.0" ?>
        <a id="a">
            <b id="b">1 1 1</b>
            2 2 2
            <c id="c">3 3 3</c>
            4 4 4
            <d id="d" />
            <e id="e">5 5 5</e>
            <f id="f" />
        </a>
    } );

    assert( doc.declXML.tag == "xml" );
    assert( doc.declXML.attrs == [ XMLAttribute("version", "1.0") ] );
    assert( doc.root.tag == "a" );
    assert( doc.root.elems[0].tag == "b" );
    assert( doc.root.elems[1].tag == "c" );
    assert( doc.root.elems[2].tag == "d" );
    assert( doc.root.elems[3].texts == ["5 5 5"] );
    assert( doc.root.texts == [ "2 2 2", "4 4 4" ] );
    assert( doc.root.pretty == [
            "<a id=\"a\">",
            "    <b id=\"b\">",
            "        1 1 1",
            "    </b>",
            "    2 2 2",
            "    <c id=\"c\">",
            "        3 3 3",
            "    </c>",
            "    4 4 4",
            "    <d id=\"d\" />",
            "    <e id=\"e\">",
            "        5 5 5",
            "    </e>",
            "    <f id=\"f\" />",
            "</a>" ] );
}
